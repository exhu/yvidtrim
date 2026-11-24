/**
 * Text rendering benchmark: CPU time per frame, process memory and GL
 * texture memory for the `Renderer` text path. It uses only the public
 * text API, so the same source builds before and after the glyph atlas.
 *
 * Run: `./_build/textbench` (needs a display; optional arg: label).
 */
// Declared inside the yguilib package to reach package(yguilib) init.
module yguilib.internal.textbench;

import core.time : MonoTime;
import glad2.gles2;
import std.algorithm : sort;
import std.conv : to;
import std.format : format;
import std.stdio : File, stdout, writefln, writeln;
import std.string : startsWith;
import yguilib.clibs.sdl3 : yguilib_sdl3_init, yguilib_sdl3_quit;
import yguilib.render : Renderer;
import yguilib.render.render_types : ColorF, PointF;
import yguilib.window : Window;

enum int viewW = 1024;
enum int viewH = 768;
enum maxTexId = 100_000;

/// Process memory in KiB from /proc/self/status.
struct ProcMem {
  long rss;
  long peak;
}

ProcMem procMem() {
  ProcMem m;
  foreach (line; File("/proc/self/status").byLine) {
    if (line.startsWith("VmRSS:")) {
      m.rss = parseKb(line);
    } else if (line.startsWith("VmHWM:")) {
      m.peak = parseKb(line);
    }
  }
  return m;
}

long parseKb(const(char)[] line) {
  import std.algorithm : find, until;
  import std.array : array;
  import std.ascii : isDigit;
  auto d = line.find!(c => isDigit(c));
  return d.until!(c => !isDigit(c)).array.to!long;
}

extern (C) {
  struct MallInfo2 {
    size_t arena, ordblks, smblks, hblks, hblkhd, usmblks, fsmblks;
    size_t uordblks, fordblks, keepcost;
  }
  MallInfo2 mallinfo2() nothrow @nogc;
}

/// D GC heap and C heap (malloc) usage in KiB; the rest of RSS is
/// the GL driver, mapped libraries and the stack.
struct HeapMem {
  long gcUsed;
  long gcFree;
  long cUsed;
}

HeapMem heapMem() {
  import core.memory : GC;
  const s = GC.stats();
  const m = mallinfo2();
  return HeapMem(s.usedSize / 1024, s.freeSize / 1024,
    (m.uordblks + m.hblkhd) / 1024);
}

/// Live GL textures and their level-0 RGBA8 byte size.
struct GlTex {
  size_t count;
  size_t bytes;
}

GlTex glTextures() {
  GlTex t;
  GLint prev = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev);
  foreach (id; 1 .. maxTexId) {
    if (!glIsTexture(id)) {
      continue;
    }
    glBindTexture(GL_TEXTURE_2D, id);
    GLint w = 0;
    GLint h = 0;
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &w);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &h);
    t.count++;
    t.bytes += cast(size_t) w * h * 4;
  }
  glBindTexture(GL_TEXTURE_2D, prev);
  return t;
}

alias LabelFn = string delegate(int frame, int i);

struct Scenario {
  string name;
  int labels;
  int frames;
  float[] sizes;
  string fontName;
  LabelFn text;
  const(ColorF)[] colors;
}

double ms(MonoTime a, MonoTime b) {
  return (b - a).total!"nsecs" / 1.0e6;
}

void drawFrame(Renderer r, ref const Scenario s, int frame) {
  r.clearFrame(ColorF(0.1f, 0.1f, 0.1f, 1.0f));
  const white = ColorF(1, 1, 1, 1);
  foreach (i; 0 .. s.labels) {
    const float sz = s.sizes[i % s.sizes.length];
    const float x = 8.0f + (i % 4) * 250.0f;
    const float y = 4.0f + (i / 4 % 40) * 18.0f;
    const c = s.colors.length > 0 ? s.colors[i % s.colors.length] : white;
    r.drawTextWithFontName(
      s.text(frame, i), PointF(x, y), c, sz, s.fontName
    );
  }
  r.flush();
  glFinish();
}

void run(Renderer r, Scenario s) {
  r.clearTextCache();
  glFinish();
  const base = procMem();
  const heap0 = heapMem();
  const tex0 = glTextures();

  auto t0 = MonoTime.currTime;
  drawFrame(r, s, 0);
  const cold = ms(t0, MonoTime.currTime);
  const afterCold = procMem();
  const texCold = glTextures();

  auto times = new double[s.frames];
  foreach (f; 0 .. s.frames) {
    auto a = MonoTime.currTime;
    drawFrame(r, s, f + 1);
    times[f] = ms(a, MonoTime.currTime);
  }
  const end = procMem();
  const heap1 = heapMem();
  const tex1 = glTextures();
  double sum = 0;
  foreach (v; times) {
    sum += v;
  }
  times.sort();
  const avg = sum / times.length;
  const p95 = times[cast(size_t)(times.length * 95 / 100)];
  const worst = times[$ - 1];

  writefln(
    "%-10s labels=%-5d cold=%7.2fms avg=%7.3fms p95=%7.3fms max=%7.3fms",
    s.name, s.labels, cold, avg, p95, worst
  );
  writefln(
    "%-10s   rss: +%dKiB after cold, +%dKiB at end (peak %dKiB)",
    "", afterCold.rss - base.rss, end.rss - base.rss, end.peak
  );
  writefln(
    "%-10s   heap at end: gc used +%dKiB free +%dKiB, malloc +%dKiB",
    "", heap1.gcUsed - heap0.gcUsed, heap1.gcFree - heap0.gcFree,
    heap1.cUsed - heap0.cUsed
  );
  {
    // What stays after a full collection: separates GC garbage from the
    // memory the text path really holds.
    import core.memory : GC;
    GC.collect();
    GC.minimize();
    const after = procMem();
    const heap2 = heapMem();
    writefln(
      "%-10s   after GC.collect+minimize: rss +%dKiB, gc used +%dKiB, "
      ~ "malloc +%dKiB",
      "", after.rss - base.rss, heap2.gcUsed - heap0.gcUsed,
      heap2.cUsed - heap0.cUsed
    );
  }
  writefln(
    "%-10s   gl textures: +%d / +%.2fMiB after cold, +%d / +%.2fMiB at end",
    "", cast(long) texCold.count - cast(long) tex0.count,
    (texCold.bytes - tex0.bytes) / 1048576.0,
    cast(long) tex1.count - cast(long) tex0.count,
    (tex1.bytes - tex0.bytes) / 1048576.0
  );
  stdout.flush();
}

/// Draws `text` alone and prints measured size and lit pixel count/bbox.
void fidelity(Renderer r, string label, string text, float sz, string font) {
  r.clearFrame(ColorF(0, 0, 0, 1));
  r.drawTextWithFontName(text, PointF(10, 10), ColorF(1, 1, 1, 1), sz, font);
  r.flush();
  glFinish();
  auto buf = new ubyte[viewW * 200 * 4];
  glReadPixels(0, viewH - 200, viewW, 200, GL_RGBA, GL_UNSIGNED_BYTE,
    buf.ptr);
  int lit = 0;
  int x0 = int.max;
  int x1 = -1;
  foreach (y; 0 .. 200) {
    foreach (x; 0 .. viewW) {
      if (buf[(y * viewW + x) * 4] > 60) {
        lit++;
        x0 = x < x0 ? x : x0;
        x1 = x > x1 ? x : x1;
      }
    }
  }
  const m = r.measureTextWithFontName(text, sz, font);
  writefln("fidelity %-14s measure=%.1fx%.1f lit=%d x=[%d..%d]",
    label, m.x, m.y, lit, x0, x1);
}

enum cjkPath = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc";

/// Label with CJK text mixed with latin text and digits.
string mixedLabel(int f, int i) {
  return format("视频剪辑 Video Trim 第%d段 00:%02d 完成 OK", i, f % 60);
}

/// Label of distinct han characters (U+4E00..), which stresses the atlas.
string hanLabel(int f, int i) {
  dchar[] s;
  foreach (j; 0 .. 8) {
    s ~= cast(dchar)(0x4E00 + (i * 8 + j) * 3 % 6000);
  }
  return "Cn " ~ s.to!string ~ format(" #%d", i);
}

void cjkScenarios(Renderer r) {
  import std.file : exists;

  const mixed = "视频剪辑 Video Trim 第3段 完成 OK";
  writeln("-- default font (no CJK glyphs expected)");
  fidelity(r, "default-mixed", mixed, 14.0f, null);
  if (!exists(cjkPath)) {
    writeln("-- ", cjkPath, " missing, CJK font scenarios skipped");
    return;
  }
  r.registerFontFromFile("cjk", cjkPath);
  writeln("-- registered font ", cjkPath);
  fidelity(r, "cjk-mixed", mixed, 14.0f, "cjk");
  fidelity(r, "cjk-latin", "Video Trim OK", 14.0f, "cjk");
  const float[] one = [14.0f];
  const float[] three = [11.0f, 14.0f, 20.0f];
  run(r, Scenario("cjk-mix", 100, 300, three.dup, "cjk",
    (int f, int i) => mixedLabel(f, i)));
  run(r, Scenario("cjk-many", 1500, 100, one.dup, "cjk",
    (int f, int i) => hanLabel(f, i)));
}

void main(string[] args) {
  yguilib_sdl3_init();
  scope(exit) yguilib_sdl3_quit();
  auto w = new Window(viewW, viewH, "textbench");
  w.create();
  w.setDisplayScaling(1.0f);
  auto r = w.renderer;
  r.viewport(viewW, viewH);
  scope(exit) w.destroy();

  writeln("textbench ", args.length > 1 ? args[1] : "");
  const float[] one = [14.0f];
  const float[] three = [11.0f, 14.0f, 20.0f];

  // fixed labels redrawn every frame: steady state, all cache hits
  run(r, Scenario("static", 200, 300, three.dup, null,
    (int f, int i) => format("Label %d: the quick brown fox", i)));
  // digits change every frame: timecodes and counters
  run(r, Scenario("churn", 100, 300, one.dup, null,
    (int f, int i) => format("%02d:%02d:%02d.%03d", i, f / 60, f % 60,
      (f * 7 + i) % 1000)));
  // 1500 labels (exceeded the historical 512 cap, fits inside the 2048 cap)
  run(r, Scenario("many", 1500, 100, three.dup, null,
    (int f, int i) => format("Item %04d / file_%d.mp4", i, i * 37)));
  // more distinct strings per frame than the hard cap (2 * 2048)
  run(r, Scenario("thrash", 5000, 50, three.dup, null,
    (int f, int i) => format("Item %04d / file_%d.mp4", i, i * 37)));
  // 200 labels cycling 4 colors: verifies per-vertex color batching
  const ColorF[] palette = [
    ColorF(1.0f, 0.3f, 0.3f, 1.0f),
    ColorF(0.3f, 1.0f, 0.3f, 1.0f),
    ColorF(0.3f, 0.6f, 1.0f, 1.0f),
    ColorF(1.0f, 0.85f, 0.2f, 1.0f),
  ];
  run(r, Scenario("multicolor", 200, 300, three.dup, null,
    (int f, int i) => format("Label %d: the quick brown fox", i), palette));
  cjkScenarios(r);
}
