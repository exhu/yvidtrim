# Memory & Performance Optimization Plan — Widget Draw Pipeline

Analysis and optimization proposals for `collectVisibleWidgets`,
`drawWidgetTree` (in `uisystem.d`), and `WidgetPainterSystem`
(in `widget_painter.d`).

> [!NOTE]
> This plan is analysis-only — no code changes are made. Each section
> identifies the problem, proposes a fix, and shows the expected code shape.

---

## Background

The draw pipeline today works like this:

```
drawUi()
  └─ drawWidgetTree(root)
       ├─ collectVisibleWidgets(root)   → Widget[] (GC heap)
       ├─ prepend root                  → [root] ~ collected (GC heap)
       └─ painterSystem.drawWidgets(array, renderer)
            └─ foreach widget → drawWidget(w, r)
                                  └─ per-component GL calls
```

Every frame this path:

1. **Allocates** a new `Widget[]` via GC `~=` (append) for every tree level
   recursively.
2. **Concatenates** `[root] ~ collected` — yet another GC allocation.
3. Passes the flat array to `WidgetPainterSystem.drawWidgets`, which issues
   **individual GL draw calls** per widget component (background, text, border).

---

## 1. `collectVisibleWidgets` — Excessive GC Allocations

### Problem

```d
// Current code (uisystem.d:202-214)
Widget[] collectVisibleWidgets(Widget root) {
  if (!root.visible)
    return null;

  Widget[] result = [];
  foreach(w; root.children) {
    if (w.visible) {
      result ~= w;
      result ~= collectVisibleWidgets(w);
    }
  }
  return result;
}
```

| Issue | Impact |
|---|---|
| `result ~= w` and `result ~= collectVisibleWidgets(w)` trigger GC `~=` on every recursion level | **O(n) GC allocations** for n widgets; each `~=` may re-allocate the backing array |
| Every recursive call returns a **new** `Widget[]` that is concatenated into the parent — intermediate arrays are immediately garbage | **GC pressure** proportional to tree depth × branching factor |
| `result = []` creates a zero-length GC slice on each call | Unnecessary allocation even for leaf nodes |

### Proposed Fix — Reuse a Flat Buffer, Walk In-Place

Replace the recursive method with an **iterative pre-order DFS** that appends
into a **reusable `Appender`** member field, avoiding per-frame GC allocations
entirely.

```d
import std.array : Appender;

// New member in UiSystem (replaces per-call allocations)
Appender!(Widget[]) visibleBuf;

// Replaces both collectVisibleWidgets + drawWidgetTree
private void drawWidgetTree(Widget root) {
  if (root is null || !root.visible)
    return;
  visibleBuf.clear();            // reuse backing memory
  collectVisible(root);          // fill buffer
  painterSystem.drawWidgets(
    visibleBuf[], mainWindow.renderer
  );
}

// Iterative pre-order DFS (no recursion, no intermediate arrays)
private void collectVisible(Widget root) {
  visibleBuf ~= root;
  foreach (w; root.children) {
    if (w.visible)
      collectVisible(w);
  }
}
```

**Why `Appender`?** `std.array.Appender` keeps its backing array alive across
`clear()` calls, so subsequent frames reuse the same memory. The GC sees a
single live allocation that grows to a high-water mark and stays there.

**Alternative — explicit stack for iteration:**

If the widget tree becomes very deep (hundreds of levels — unlikely in a UI),
a manual stack avoids D call-stack overflow. For typical UIs (< 20 levels),
the recursive approach above is fine and simpler.

### Complexity

| Metric | Before | After |
|---|---|---|
| GC allocations per frame | O(nodes) | **0** (amortized) |
| Array copies per frame | O(nodes × depth) | **0** |
| CPU overhead | ~2× due to copies | ~1× single walk |

---

## 2. `drawWidgetTree` — Redundant Concatenation

### Problem

```d
// Current code (uisystem.d:216-219)
void drawWidgetTree(Widget root) {
  Widget[] collected = [root] ~ collectVisibleWidgets(root);
  painterSystem.drawWidgets(collected, mainWindow.renderer);
}
```

`[root] ~ collectVisibleWidgets(root)` allocates a **third** array just to
prepend the root. The root can simply be the first element pushed in the
collection pass (as shown in §1).

### Proposed Fix

Included in the §1 rewrite above — `collectVisible(root)` pushes `root`
first, eliminating the concatenation.

---

## 3. `WidgetPainterSystem` — Per-Widget GL State Thrashing

### Problem

```d
// Current code (widget_painter.d:5-27)
void drawWidgets(Widget[] widgets, Renderer r) {
  foreach(w; widgets)
    drawWidget(w, r);
}

static void drawWidget(Widget w, Renderer r) {
  if (w.clipContents)
    r.pushClipRect(w.rect);

    if (w.components.background !is null)
      drawBackground(w, r);
    if (w.components.textLabel !is null)
      drawTextLabel(w, r);
    if (w.components.border !is null)
      drawBorder(w, r);

  if (w.clipContents)
    r.popClipRect();
}
```

Each `drawBackground`, `drawTextLabel`, `drawBorder` call goes through the
renderer, which does:

1. `glUseProgram(...)` — shader switch
2. `glUniform*` — uniform uploads
3. `glBufferData` — vertex upload
4. `glDrawArrays` — draw call

For **N** widgets with all three components, this emits up to **3 × N
draw calls** and **3 × N shader switches** per frame. On embedded/mobile
GLES targets the driver overhead per draw call dominates.

### 3a. Batch by Shader Program — Mid-Term Optimization

Group draw calls so all rects use one `glUseProgram`, all round-rects use
another, and text uses a third. This reduces shader switches from 3N to 3.

Sketch (conceptual — not full implementation):

```d
void drawWidgets(Widget[] widgets, Renderer r) {
  // Pass 1: backgrounds (rect / roundRect shader)
  foreach (w; widgets) {
    if (w.clipContents)
      r.pushClipRect(w.rect);
    if (w.components.background !is null)
      drawBackground(w, r);
    if (w.clipContents)
      r.popClipRect();
  }
  // Pass 2: text (texture shader)
  foreach (w; widgets) {
    if (w.clipContents)
      r.pushClipRect(w.rect);
    if (w.components.textLabel !is null)
      drawTextLabel(w, r);
    if (w.clipContents)
      r.popClipRect();
  }
  // Pass 3: borders (roundRect shader)
  foreach (w; widgets) {
    if (w.clipContents)
      r.pushClipRect(w.rect);
    if (w.components.border !is null)
      drawBorder(w, r);
    if (w.clipContents)
      r.popClipRect();
  }
}
```

> [!WARNING]
> Multi-pass rendering **changes the draw order**: borders of widget A will
> draw after backgrounds of widget B. This is correct only if the Z-order is
> implicitly: all backgrounds → all text → all borders. This is often fine
> for non-overlapping widget trees, but needs validation for overlapping
> widgets with mixed component layers. If overlap matters, the batch must
> be done per-clip-group (widgets sharing the same clip rect) or a more
> sophisticated sorting approach is needed. **Skipping this optimization is
> reasonable until profiling shows shader switches are the bottleneck.**
>
> **Why a Z-buffer doesn't fix this.** A natural thought is to assign per-widget
> depth values and let `GL_DEPTH_TEST` enforce correct ordering regardless of
> draw-call order. However, this renderer uses
> `glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)` for *all* geometry, and
> semi-transparent fragments are pervasive:
>
> - **Round rect corners** — the SDF fragment shader produces anti-aliased
>   edges by outputting fractional alpha.
> - **Text quads** — TTF glyphs are rasterized with alpha-blended edges.
> - **Explicit translucency** — UI elements may use partial opacity.
>
> If a semi-transparent fragment (e.g. α=0.3 at an AA edge) writes to the
> depth buffer, it blocks later fragments behind it from blending correctly,
> producing hard-edged cutouts instead of smooth AA. The textbook workaround
> (opaque front-to-back with depth write ON, then transparent back-to-front
> with depth write OFF) doesn't help here because nearly *all* geometry has
> transparency at its edges. Splitting every widget into "opaque interior" +
> "transparent fringe" passes would be far more complex than the single-pass
> painter's-algorithm approach the current code already uses.
>
> **Painter's algorithm (back-to-front draw order) is the correct approach
> for a 2D UI renderer built around alpha blending.**

#### When to Profile §3a

**1. Instrument draw call counts (cheapest, do first).** Add counters to
`Renderer` that track per-frame stats — no external tools needed:

```d
// In Renderer, reset at frame start, read at frame end
struct FrameStats {
  uint drawCalls;
  uint shaderSwitches;
  uint bufferUploads;
}
```

Increment in `drawArrays`, `drawRoundRectImpl`, `drawTexture`, and wherever
`glUseProgram` is called. Log or overlay the numbers. This tells you **how
many** calls you're making but not **how expensive** each one is.

**2. Wall-clock frame timing (simple, catches gross problems).** Wrap
`drawWidgets` with a monotonic clock:

```d
import core.time : MonoTime;
auto t0 = MonoTime.currTime;
glFinish();  // force GPU to complete — essential for accurate timing
auto elapsed = MonoTime.currTime - t0;
```

`glFinish()` is critical — without it you're only measuring CPU-side command
submission, not actual GPU work. Compare elapsed time with growing widget
counts (50, 200, 500) to see if it scales linearly or worse.

**3. Synthetic stress test (the decision-maker).** Create a throwaway test
that builds a flat tree of N widgets (all with background + text + border)
and times `drawWidgets`. Run it with N = 50, 200, 500, 1000. Plot frame
time vs N. If the curve is **linear**, shader switches aren't the
bottleneck (the per-call overhead is constant and tolerable). If it's
**super-linear**, driver overhead from state changes is compounding.

**4. `apitrace` (when you need the full picture).**

```bash
apitrace trace --api egl ./your_app    # capture GL call stream
apitrace replay app.trace              # replay
qapitrace app.trace                    # GUI: see every call, state, timing
```

This shows the exact sequence of `glUseProgram` → `glUniform*` →
`glBufferData` → `glDrawArrays` calls per frame with timing. You can
visually spot redundant shader switches.

**5. `GALLIUM_HUD` (Mesa drivers only, zero code changes).**

```bash
GALLIUM_HUD="fps,cpu+GPU-load" ./your_app
```

Overlays live FPS and GPU utilization. If GPU load is low while frame times
are high, it's likely CPU-side driver overhead (draw call submission) —
which is exactly what batching fixes.

**When to act.** The batching optimization (§3a) is worth pursuing when:

- Draw call count exceeds **~200–300 per frame** (a rough rule of thumb for
  GLES on embedded/mobile — desktop GPUs tolerate much more).
- Frame time for `drawWidgets` exceeds your frame budget (e.g. >4ms for
  60fps leaves room for event handling and layout).
- `apitrace` shows repeated `glUseProgram` calls alternating between the
  same 2–3 programs.

#### Alternative: Uber-Shader (Merging Programs)

Instead of batching by shader program (§3a), merge all three programs
(`color`, `texture`, `roundrect`) into a single shader with a
`uniform int uMode;` branch:

```glsl
if (uMode == 0) {        // solid color
  fragColor = uColor;
} else if (uMode == 1) { // textured quad
  fragColor = texture(uTexture, vTexCoord) * uColor;
} else {                  // SDF round rect
  // ... distance field, dash, AA logic
}
```

Since `uMode` is a **uniform** (not per-fragment), all fragments in a draw
call take the same branch — no warp/wavefront divergence within a call.
Modern GPU compilers handle this well.

**Tradeoffs:**

| Concern | Impact |
|---|---|
| **Register pressure** | The GPU compiler allocates registers for the worst-case path (the SDF round rect with dash/AA logic). On mobile GLES (Mali, Adreno, PowerVR) this reduces occupancy — fewer concurrent fragment threads. Every `drawFillRect` pays for round-rect complexity it doesn't use. |
| **Uniform bloat** | All uniforms from all three shaders must exist (`uHalfSize`, `uRadius`, `uDashLen`, `uTexture`, etc.) even when unused. Minor on desktop, noticeable on GLES with small uniform banks. |
| **Texture sampler binding** | The texture path needs a `sampler2D`. Non-texture draw calls must still have a valid texture bound (or guard the sample). Some GLES drivers may still touch the texture unit. |
| **Maintenance** | One 80+ line fragment shader with three interleaved code paths vs. three focused 10–20 line shaders. Harder to reason about and modify. |

**Verdict.** The uber-shader alone is a **marginal win with real maintenance
cost** — it removes `glUseProgram` switches but keeps per-widget
`glBufferData` + `glDrawArrays` calls, which are usually the larger overhead.
It becomes a **major win** when combined with **geometry batching** — packing
multiple quads into a single VBO with mode as a per-vertex attribute,
reducing the entire frame to 1–3 draw calls. That is a substantially larger
refactor (per-vertex attributes, text texture atlas, etc.) and should only
be pursued when profiling confirms draw-call overhead is the bottleneck.

### 3b. `glBufferSubData` Instead of `glBufferData` — Quick Win

In `Renderer.drawArrays`, `drawRoundRectImpl`, and `drawTexture`, each call
uses `glBufferData` with `GL_DYNAMIC_DRAW`, which **orphans and reallocates**
the buffer every time. For fixed-size vertex payloads (6 or 4 vertices),
using `glBufferSubData` into a pre-sized buffer avoids driver-side allocation:

```d
// One-time in initialize():
glBufferData(GL_ARRAY_BUFFER,
  MAX_QUAD_BYTES, null, GL_DYNAMIC_DRAW);

// Per draw call:
glBufferSubData(GL_ARRAY_BUFFER, 0,
  cast(GLsizeiptr)(vertices.length * float.sizeof),
  vertices.ptr);
```

This is a small, safe change with measurable impact on GLES drivers that
have costly `glBufferData` orphaning.

### 3c. Skip Off-Screen Widgets — Visibility Culling

Currently every visible widget is drawn regardless of whether it's within the
viewport. Adding a simple AABB check before issuing GL calls:

```d
static bool isOnScreen(in RectF rect, float vw, float vh) {
  return rect.x < vw && rect.y < vh
    && rect.x + rect.width > 0
    && rect.y + rect.height > 0;
}

static void drawWidget(Widget w, Renderer r) {
  if (!isOnScreen(w.rect, r.getLogicWidth(), r.getLogicHeight()))
    return;
  // ... existing draw logic
}
```

This is zero-cost for on-screen widgets and saves all GL work for off-screen
ones — relevant for scrollable containers.

---

## 4. `clipStack` in Renderer — Minor Allocation

### Problem

`Renderer.pushClipRect` uses `clipStack ~= clipped` which is a GC append.
For typical UIs the clip stack is shallow (≤ 10), so this is minor, but
avoidable.

### Proposed Fix

Use a static fixed-capacity array (e.g. `RectF[16]` + length counter) or an
`Appender!(RectF[])`.

```d
// Replace:
//   RectF[] clipStack;
// With:
Appender!(RectF[]) clipStack;

// pushClipRect:
clipStack ~= clipped;          // same syntax, no GC alloc

// popClipRect:
auto data = clipStack[];
clipStack.shrinkTo(data.length - 1);

// resetClipRect:
clipStack.clear();
```

This is a minor improvement but follows the same pattern as §1.

---

## 5. `WidgetComponents` — Nullable Overhead

### Problem

`WidgetComponents` stores component references as class pointers (nullable).
Each `drawWidget` call checks `!is null` for up to 4 components. This is
cheap per-check, but can cause branch mispredictions when component presence
varies across widgets.

### Proposed Fix (Future)

No immediate code change needed. If profiling shows this as hot, consider
a bitmask field:

```d
struct WidgetComponents {
  enum Has : ubyte {
    background = 1,
    textLabel = 2,
    border = 4,
    customDraw = 8,
  }
  Has present;  // set on assignment
  // ...
}
```

This converts 4 pointer-null-checks into a single bitmask test, which is more
branch-predictor-friendly. **Low priority — measure first.**

---

## Summary — Priority & Risk Matrix

| # | Change | Impact | Risk | Priority |
|---|--------|--------|------|----------|
| 1 | `Appender` buffer for `collectVisibleWidgets` | High — eliminates all per-frame GC allocs in draw path | Low — internal refactor, no API change | **P0** |
| 2 | Remove `[root] ~` concatenation | Medium — one fewer allocation | None — included in §1 | **P0** |
| 3c | Viewport culling in `drawWidget` | Medium — skips GL calls for off-screen widgets | Very low — additive check | **P1** |
| 3b | `glBufferSubData` pre-sized buffers | Low-Medium — reduces driver alloc overhead | Low — straightforward GL change | **P2** |
| 3a | Multi-pass shader batching | High (at scale) — reduces shader switches 3N → 3 | Medium — changes draw order, needs overlap validation | **P3** |
| 4 | `Appender` for `clipStack` | Low — shallow stack | None | **P3** |
| 5 | Component bitmask | Low — micro-optimization | Low | **P4** |

---

## Verification Plan

### Automated Tests

```bash
ninja -C _build && meson test -C _build
```

All existing unit tests in `uisystem.d`, `widget_painter.d`, and `render.d`
must pass unchanged. The optimization is purely internal and should not
change any observable behavior.

### Manual Verification

- Build and run the application with a non-trivial widget tree (10+ widgets).
- Verify visual output is identical to before the change.
- For §3c (viewport culling), verify that scrolling a widget off-screen and
  back produces correct rendering.
- Optional: use a GC profiler (`--DRT-gcopt=profile:1`) or `/usr/bin/time
  -v` to confirm reduced GC allocation counts.
