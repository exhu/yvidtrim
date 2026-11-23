/**
 * Optional resource telemetry (peak texture and heap usage) compiled in only
 * with `version (MemTelemetry)`, set by the Meson `memtelemetry` option.
 * Without the version every telemetry entry point is an empty stub.
 *
 * Texture tracking is main-thread only, like all GL access.
 */
module yguilib.internal.memstats;

package(yguilib):

version (MemTelemetry) {
  /// Tracks live textures and the peaks of their count and size.
  struct TextureStats {
    struct Dim {
      int w;
      int h;
    }

    Dim[uint] live;
    ulong curBytes;
    ulong peakBytes;
    size_t peakCount;
    Dim maxDim;
    ulong maxBytes;

    /// Records creation of texture `id` or re-specification of its image.
    void onAlloc(uint id, int w, int h) {
      if (auto p = id in live) {
        curBytes -= bytesOf(*p);
      }
      live[id] = Dim(w, h);
      const b = bytesOf(Dim(w, h));
      curBytes += b;
      if (curBytes > peakBytes) {
        peakBytes = curBytes;
      }
      if (live.length > peakCount) {
        peakCount = live.length;
      }
      if (b > maxBytes) {
        maxBytes = b;
        maxDim = Dim(w, h);
      }
    }

    /// Records deletion of texture `id`.
    void onFree(uint id) {
      if (auto p = id in live) {
        curBytes -= bytesOf(*p);
        live.remove(id);
      }
    }

    static ulong bytesOf(Dim d) {
      return cast(ulong) d.w * d.h * 4;
    }
  }

  /// Peaks of D GC heap and C (malloc) heap usage.
  struct HeapStats {
    ulong maxGcUsed;
    ulong maxGcTotal;
    ulong maxCUsed;

    void sample() {
      import core.memory : GC;
      const s = GC.stats();
      if (s.usedSize > maxGcUsed) {
        maxGcUsed = s.usedSize;
      }
      if (s.usedSize + s.freeSize > maxGcTotal) {
        maxGcTotal = s.usedSize + s.freeSize;
      }
      const c = cHeapUsed();
      if (c > maxCUsed) {
        maxCUsed = c;
      }
    }
  }

  version (CRuntime_Glibc) {
    private extern (C) {
      struct MallInfo2 {
        size_t arena, ordblks, smblks, hblks, hblkhd, usmblks, fsmblks;
        size_t uordblks, fordblks, keepcost;
      }
      MallInfo2 mallinfo2() nothrow @nogc;
    }

    private ulong cHeapUsed() {
      const m = mallinfo2();
      return m.uordblks + m.hblkhd;
    }
  } else {
    private ulong cHeapUsed() {
      return 0;
    }
  }

  private __gshared TextureStats gTextures;
  private __gshared HeapStats gHeap;

  void telemetryTextureAlloc(uint id, int w, int h) {
    gTextures.onAlloc(id, w, h);
  }

  void telemetryTextureFree(uint id) {
    gTextures.onFree(id);
  }

  void telemetrySampleHeap() {
    gHeap.sample();
  }

  /// Logs the peaks collected so far at info level.
  void logMemStats() {
    import std.logger : infof;
    import yguilib.texthelpers : formatBytes;
    gHeap.sample();
    infof(
      "Texture stats (RGBA8 textures only): max memory=%s, "
      ~ "max count=%s, largest=%dx%d (%s)",
      formatBytes(gTextures.peakBytes), gTextures.peakCount,
      gTextures.maxDim.w, gTextures.maxDim.h,
      formatBytes(gTextures.maxBytes)
    );
    infof(
      "Heap stats: max GC used=%s, max GC total=%s, max non-GC=%s",
      formatBytes(gHeap.maxGcUsed), formatBytes(gHeap.maxGcTotal),
      formatBytes(gHeap.maxCUsed)
    );
  }

  unittest {
    TextureStats t;
    t.onAlloc(1, 10, 10);
    t.onAlloc(2, 20, 5);
    assert(t.curBytes == 800);
    assert(t.peakCount == 2);
    t.onAlloc(1, 30, 10); // resize replaces the old size
    assert(t.curBytes == 400 + 1200);
    assert(t.peakBytes == 1600);
    assert(t.maxDim == TextureStats.Dim(30, 10));
    assert(t.maxBytes == 1200);
    t.onFree(1);
    t.onFree(1); // double free is harmless
    assert(t.curBytes == 400);
    assert(t.peakBytes == 1600);
    assert(t.peakCount == 2);
  }

  unittest {
    HeapStats h;
    h.sample();
    assert(h.maxGcTotal >= h.maxGcUsed);
  }
} else {
  void telemetryTextureAlloc(uint, int, int) {}
  void telemetryTextureFree(uint) {}
  void telemetrySampleHeap() {}
  void logMemStats() {}
}
