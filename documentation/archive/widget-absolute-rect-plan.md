# Fix Widget Painting Coordinates — Absolute Rect Propagation

## Problem

`Widget.rect` is always **parent-relative**: a child at `RectF(15, 15, 130, 90)` sits
15 units from the parent's top-left, not from the screen origin.

`UiSystem.collectVisible` already computes the correct **absolute rectangle** (`absRect`)
for each widget during the DFS traversal — it needs this to cull off-screen widgets.
However, it only pushes the raw `Widget` pointer into `visibleBuf` and throws away `absRect`.

`WidgetPainterSystem.drawWidget` then paints using `w.rect` (the relative rect) for
every renderer call:
- `r.pushClipRect(w.rect)` — clips to the wrong screen region
- `r.drawFillRect(w.rect, ...)` — fills the wrong rect
- `r.drawRect(w.rect, ...)` — outlines the wrong rect
- `r.drawFillRoundRect(w.rect, ...)` / `drawRoundRect` / `drawRoundRectDashed`
- `r.drawText(... PointF(w.rect.x, w.rect.y), ...)` — positions text incorrectly

**Fix:** Introduce a `VisibleWidget` struct carrying both the `Widget` pointer and its
computed `absRect`. Store these in `visibleBuf`. Pass them into `drawWidgets` /
`drawWidget`, which switches all draw calls from `w.rect` to `absRect`.

---

## Flow Diagram

```
collectVisible(w, parentX, parentY, vw, vh)
  │  absX = parentX + w.rect.x
  │  absY = parentY + w.rect.y
  │  absRect = RectF(absX, absY, w.rect.width, w.rect.height)
  ├─ isOnScreen? → no → skip subtree
  └─ yes → visibleBuf ~= VisibleWidget(w, absRect)
              → recurse children with (absX, absY)

drawWidgets(VisibleWidget[] vws, Renderer r)
  └─ drawWidget(vw.widget, vw.absRect, r)
       ├─ pushClipRect(absRect)
       ├─ drawBackground(absRect, ...)
       ├─ drawBorder(absRect, ...)
       ├─ drawTextLabel(PointF(absRect.x, absRect.y), ...)
       └─ popClipRect()
```

---

## Changes

### `yguilib/source/yguilib/uisystem.d`

1. **Add `VisibleWidget` struct** at package scope:
   ```d
   package struct VisibleWidget {
     Widget widget;
     RectF absRect;
   }
   ```

2. **Change `visibleBuf` type:**
   ```diff
   -  Appender!(Widget[]) visibleBuf;
   +  Appender!(VisibleWidget[]) visibleBuf;
   ```

3. **Push `VisibleWidget` in `collectVisible`:**
   ```diff
   -    visibleBuf ~= w;
   +    visibleBuf ~= VisibleWidget(w, absRect);
   ```

4. **Update unit test** to use `.widget` and add `.absRect` assertions.

---

### `yguilib/source/yguilib/widget_painter.d`

1. **Import `VisibleWidget`:**
   ```d
   import yguilib.uisystem : VisibleWidget;
   ```

2. **Change `drawWidgets` to accept `VisibleWidget[]`:**
   ```d
   void drawWidgets(VisibleWidget[] widgets, Renderer r) {
     foreach (ref vw; widgets)
       drawWidget(vw.widget, vw.absRect, r);
   }
   ```

3. **Add `absRect` parameter to `drawWidget`, `drawBackground`, `drawBorder`,
   `drawTextLabel`; replace all `w.rect` usages with `absRect`.**

4. **Update class doc comment** to note that `Widget.rect` is parent-relative and
   `absRect` is resolved by `UiSystem.collectVisible`.

---

## Verification

```bash
ninja -C _build && meson test -C _build
```
All 5 test suites must pass. The `collectVisible` unit test gains `absRect` assertions.
