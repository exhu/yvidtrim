/**
 * Per-frame vertex batcher for glyph quads across consecutive text draws
 * sharing the same atlas texture and stencil-clip state.
 */
module yguilib.render.internal.text_batch;

package(yguilib):

import glad2.gles2;
import yguilib.render.internal.gl_util : maxIndexedQuads;
import yguilib.render.internal.pipelines : TextPipeline, TextVertex, Viewport;
import yguilib.render.internal.stencil_ops : beginClipTest, endStencil;

version (unittest) {
  /// Diagnostic counters recorded across `TextBatch.flush` calls.
  struct TextBatchStats {
    size_t flushes;
    size_t flushedQuads;
  }
}

/**
 * Accumulates `TextVertex[4]` glyph quads for a single `(texture,
 * stencilClip)` state and submits them as one indexed draw on `flush`.
 */
struct TextBatch {
  @disable this(this);

  /// True when no quads are queued.
  bool empty() const nothrow @safe {
    return fQuadCount == 0;
  }

  /// Number of queued glyph quads.
  size_t quadCount() const nothrow @safe {
    return fQuadCount;
  }

  /// Texture id of the active batch (0 when empty).
  GLuint texture() const nothrow @safe {
    return fTexture;
  }

  /// Stencil clip state of the active batch (`false` when empty).
  bool stencilClip() const nothrow @safe {
    return fStencilClip;
  }

  /**
   * True when queuing a quad for `(texId, stencilClip)` cannot merge into
   * the current batch because state differs or `maxIndexedQuads` is full.
   */
  bool needsFlushFor(GLuint texId, bool stencilClip) const nothrow @safe {
    return fQuadCount > 0 && (
      fTexture != texId || fStencilClip != stencilClip
      || fQuadCount >= maxIndexedQuads
    );
  }

  /**
   * Appends one glyph quad (`4` vertices) to the current batch.
   * Requires `texId != 0` and `!needsFlushFor(texId, stencilClip)`.
   */
  void pushQuad(GLuint texId, bool stencilClip, in TextVertex[4] quad) {
    assert(texId != 0);
    assert(!needsFlushFor(texId, stencilClip));
    if (fQuadCount == 0) {
      fTexture = texId;
      fStencilClip = stencilClip;
    }
    appendQuad(quad);
  }

  /// Number of quads that still fit before `maxIndexedQuads`.
  size_t remaining() const nothrow @safe {
    return maxIndexedQuads - fQuadCount;
  }

  /**
   * Sets the batch state for a run of quads appended with `appendQuad`.
   * Requires `texId != 0` and `!needsFlushFor(texId, stencilClip)`.
   */
  void beginRun(GLuint texId, bool stencilClip) {
    assert(texId != 0);
    assert(!needsFlushFor(texId, stencilClip));
    fTexture = texId;
    fStencilClip = stencilClip;
  }

  /**
   * Appends one quad without state checks; requires `remaining() > 0` and
   * a prior `beginRun` (or `pushQuad`) for the current batch state.
   */
  void appendQuad(in TextVertex[4] quad) {
    assert(fQuadCount < maxIndexedQuads);
    if (fVerts.length == 0) {
      fVerts = new TextVertex[maxIndexedQuads * 4];
    }
    fVerts[fQuadCount * 4 .. fQuadCount * 4 + 4] = quad[];
    ++fQuadCount;
  }

  /**
   * Draws all queued quads through `pipeline` and resets batch state.
   * Clears internal state before issuing GL calls.
   */
  void flush(ref TextPipeline pipeline, in Viewport vp) {
    if (fQuadCount == 0) {
      return;
    }
    const GLuint tex = fTexture;
    const bool clip = fStencilClip;
    const size_t quads = fQuadCount;
    const(TextVertex)[] verts = fVerts[0 .. quads * 4];
    fQuadCount = 0;
    fTexture = 0;
    fStencilClip = false;

    if (clip) {
      beginClipTest(true);
    }
    pipeline.drawGlyphQuads(tex, verts, quads, vp);
    if (clip) {
      endStencil();
    }

    version (unittest) {
      ++fStats.flushes;
      fStats.flushedQuads += quads;
    }
  }

  /// Drops queued quads while keeping the backing vertex buffer capacity.
  void clear() {
    fQuadCount = 0;
    fTexture = 0;
    fStencilClip = false;
  }

  /// Drops queued quads and releases the backing vertex buffer.
  void releaseMemory() {
    fVerts = null;
    fQuadCount = 0;
    fTexture = 0;
    fStencilClip = false;
  }

  version (unittest) {
    TextBatchStats stats() const nothrow @safe {
      return fStats;
    }

    void resetStats() nothrow @safe {
      fStats = TextBatchStats.init;
    }
  }

private:
  TextVertex[] fVerts;
  size_t fQuadCount;
  GLuint fTexture;
  bool fStencilClip;
  version (unittest) {
    TextBatchStats fStats;
  }
}

unittest {
  TextBatch batch;
  assert(batch.empty());
  assert(batch.quadCount() == 0);
  assert(batch.texture() == 0);
  assert(!batch.stencilClip());
  assert(!batch.needsFlushFor(1, false));
  assert(!batch.needsFlushFor(1, true));

  const TextVertex[4] q = [
    TextVertex(0, 0, 0, 0, [255, 255, 255, 255]),
    TextVertex(10, 0, 1, 0, [255, 255, 255, 255]),
    TextVertex(0, 10, 0, 1, [255, 255, 255, 255]),
    TextVertex(10, 10, 1, 1, [255, 255, 255, 255]),
  ];

  batch.pushQuad(7, true, q);
  assert(!batch.empty());
  assert(batch.quadCount() == 1);
  assert(batch.texture() == 7);
  assert(batch.stencilClip());

  // Same state fits; texture or clip mismatch requires flush.
  assert(!batch.needsFlushFor(7, true));
  assert(batch.needsFlushFor(8, true));
  assert(batch.needsFlushFor(7, false));

  batch.clear();
  assert(batch.empty());
  assert(batch.quadCount() == 0);
  assert(batch.texture() == 0);
  assert(!batch.stencilClip());
  assert(!batch.needsFlushFor(8, false));

  // Boundary at maxIndexedQuads.
  foreach (_; 0 .. maxIndexedQuads - 1) {
    batch.pushQuad(5, false, q);
    assert(!batch.needsFlushFor(5, false));
  }
  batch.pushQuad(5, false, q);
  assert(batch.quadCount() == maxIndexedQuads);
  assert(batch.needsFlushFor(5, false));

  batch.releaseMemory();
  assert(batch.empty());
  assert(batch.quadCount() == 0);
  assert(batch.texture() == 0);
  assert(!batch.stencilClip());
}

unittest {
  import core.memory : GC;

  TextBatch batch;
  const TextVertex[4] q = [
    TextVertex(0, 0, 0, 0, [255, 255, 255, 255]),
    TextVertex(8, 0, 1, 0, [255, 255, 255, 255]),
    TextVertex(0, 8, 0, 1, [255, 255, 255, 255]),
    TextVertex(8, 8, 1, 1, [255, 255, 255, 255]),
  ];

  // Warm up buffer capacity.
  foreach (_; 0 .. 128) {
    batch.pushQuad(1, false, q);
  }
  batch.clear();

  GC.collect();
  const before = GC.stats();
  foreach (_; 0 .. 200) {
    foreach (i; 0 .. 64) {
      batch.pushQuad(1, false, q);
    }
    batch.clear();
  }
  const after = GC.stats();
  assert(after.allocatedInCurrentThread == before.allocatedInCurrentThread);
  assert(
    after.usedSize + after.freeSize <= before.usedSize + before.freeSize
  );
  batch.releaseMemory();
}
