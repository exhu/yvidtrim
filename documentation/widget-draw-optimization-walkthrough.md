# Walkthrough — Widget Draw Pipeline & Clip Stack Optimizations

Optimization of `collectVisibleWidgets`, `drawWidgetTree`, and `clipStack` by using `Appender`, along with viewport culling of off-screen widgets (and their child subtrees) taking parent-relative coordinates into account.

## Summary of Changes

### 1. Reusable Buffer for Widget Collection (`UiSystem`)
- **Problem**: `collectVisibleWidgets` recursively allocated intermediate `Widget[]` dynamic arrays via `~=`, and `drawWidgetTree` allocated a third array to prepend the root: `[root] ~ collected`.
- **Solution**:
  - Replaced the recursive allocating function with a single traversal `collectVisible` using a persistent member `Appender!(Widget[]) visibleBuf`.
  - Reused `visibleBuf` across frames by clearing it with `visibleBuf.clear()`.
  - Added root as the first element in pre-order DFS, eliminating `[root] ~ ...` concatenation completely.

### 2. Viewport Culling with Parent-Relative Coordinates (`UiSystem` & `WidgetPainterSystem`)
- **Problem**: Previously, all visible widgets were drawn even if located outside the visible screen.
- **Solution**:
  - Implemented `UiSystem.isOnScreen(rect, vw, vh)` to test intersection with the logical viewport (`[0, vw] x [0, vh]`).
  - Accounted for parent-relative coordinates: accumulated `(parentX, parentY)` during tree traversal to compute each widget's absolute rectangle `RectF(parentX + w.rect.x, parentY + w.rect.y, w.rect.width, w.rect.height)`.
  - If a parent widget is off-screen, both the parent and its entire subtree of children are skipped immediately.
  - Culled widgets are never added to `visibleBuf`, guaranteeing zero GL draw or scissor clip calls in `Renderer`.
  - Added class-level documentation to `WidgetPainterSystem` describing this culling behavior.

### 3. Clip Stack Allocation Removal (`Renderer`)
- **Problem**: `Renderer.pushClipRect`, `popClipRect`, `setClipRect`, and `resetClipRect` manipulated `RectF[] clipStack` via array appends and slices, causing heap allocations.
- **Solution**:
  - Converted `clipStack` to `Appender!(RectF[])`.
  - Reused buffer memory via `clipStack ~= clipped`, `clipStack.shrinkTo(...)`, and `clipStack.clear()`.

---

## Verification Results

### Automated Tests
Run via Meson and Ninja:
```bash
ninja -C _build && meson test -C _build
```
All 5 test suites pass:
- `yguilib_sdl3_ttf`: OK
- `glad2gles31d`: OK
- `yvidtrim_sdl3`: OK
- `yguilib_sdl3`: OK
- `yguilib_test`: OK (including new tests for `isOnScreen`, off-screen parent & child subtree culling, and `clipStack` Appender operations)
