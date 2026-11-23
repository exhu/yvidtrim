# Canvas ph05: CustomDraw hookup and guidemo Canvas page

Overview: [canvas.md](canvas.md). Read `AGENTS.md` (the View/Controller
separation and timer rules) and `codestyle.md` first.

## Context
- From ph01–ph04, `Renderer.canvas()` returns a working `Canvas` (fill,
  stroke, clip, transforms, save/restore, gradients, clearRect) and
  `Path2d`, from `yguilib.render.canvas`.
- `widget/drawing_components.d:164` declares
  `class CustomDraw : WidgetComponent { void delegate(in Renderer r, in
  Widget w) drawFunc; }`. `widget/builder.d:554` has
  `onDraw(void delegate(in Renderer, in Widget))`.
  `widget/package.d:78` has the `customDraw` field.
- `widget/internal/widget_painter.d`'s `drawWidget` has
  `// TODO CustomWidgetPainter.drawContent` after the text label, inside
  the `clipContents` push/pop, and never invokes `customDraw`.
- Guidemo pages live in `source/guidemo/pages/*_page.d` and
  `*_controller.d`. The simplest template is `knob_page.d` and
  `knob_controller.d`. Registration:
  - `DemoPage` enum and the `demoPages` metadata in
    `source/guidemo/model.d`;
  - a `*PageModel` class in `model.d`;
  - `registerSimplePage!(Page, Controller, Model)` in
    `source/guidemo/guidemoapp.d` (~line 277), plus the header comment
    listing pages (~line 42);
  - sources in `guidemo_lib_src` in the root `meson.build`.
- Timers: use `TimerControl` (`startTimer` / `stopTimer`) and
  `Controller.onTimer`, and stop the timer when the page is hidden.

## Steps
1. Change `CustomDraw.drawFunc` to `void delegate(Renderer r, in Widget w)`.
   Update `WidgetBuilder.onDraw` and fix any callers (there are none
   outside the builder today; check with grep).
2. In `WidgetPainter.drawWidget`, replace the drawContent TODO with:
   ```
   if (w.components.customDraw !is null
       && w.components.customDraw.drawFunc !is null) {
     auto c = r.canvas();
     c.save();
     c.translate(PointF(absContentRect.x, absContentRect.y));
     w.components.customDraw.drawFunc(r, w);
     c.restore();
   }
   ```
   Leave the TODOs for drawBackground and drawBorder as they are. Document
   that the delegate draws in content-local coordinates through the canvas,
   while Renderer calls stay absolute (`absContentRect` is available from
   `w`).
3. Add `CanvasPageModel` (`dashOffset`, `rotation`, `animating`) and
   `DemoPage.canvas` with `DemoPageMeta("Canvas", "Canvas")` at the end of
   the enum.
4. Add `source/guidemo/pages/canvas_page.d` and `canvas_controller.d`,
   following the knob page pattern. Section cards (`makeSectionCard`) each
   have one widget with `.onDraw(&drawX)`:
   1. Paths: quadratic and cubic curves, `arc`, `arcTo`, `ellipse`,
      `roundRect`.
   2. Fill rules: the same star with nonZero and with evenOdd, side by side.
   3. Strokes: rows of caps × joins, miterLimit, dashes with `dashOffset`
      animated by the model.
   4. Transforms: a rotating shape driven by `rotation`, plus a mirrored
      `scale(-1, 1)` shape.
   5. Clip: a circle clip over stripes, plus a nested clip.
   6. Gradients: linear and radial (two-circle) fills, and a gradient
      stroke.
   7. Interop: a Renderer `drawFillRoundRect` and `drawTextWithFont`
      interleaved with Canvas fills, to show they compose.
   - Store `Path2d` objects prebuilt in the page; don't rebuild them per
     frame unless they depend on the model.
   - Animation: the controller runs a timer (~30 fps) only while the page is
     visible and `animating`; a key toggles it. Each tick advances the model,
     and the page's `update()` marks the custom-draw widgets dirty, as other
     pages do with `update(WidgetUpdateScope...)`.
   - `formatStatus()` shows the key hints.
5. Register the page in `guidemoapp.d` and add the files to `meson.build`.
6. Docs:
   - `ARCHITECTURE.md`: render/canvas, the internal flatten, stroker and
     stencil modules, the stencil bit layout, Canvas/Renderer interop,
     CustomDraw flow and the `clearFrame` rename. Keep it under 250 lines.
   - `TODO.md`: remove item 1 (the Canvas lines 1–3). Add an entry for
     Pattern/image support under "add image support" if it's missing.

## Unit tests
- Painter: a widget with `onDraw` gets its delegate called once per draw,
  with the canvas origin translated (check that `canvas` transform `e/f`
  equals the content rect origin inside the delegate). A Canvas `xf` getter
  is needed; add `Transform2d transform() const` to Canvas if it's missing.
- The guidemo Canvas page builds headlessly with `UiSystemImpl(null)`. The
  controller toggles `animating` on the key and starts and stops the timer.
  Follow the existing `knob_controller.d` tests.

## Done when
`ninja -C _build && meson test -C _build` passes and no line exceeds 80
columns. `./_build/guidemo` shows the Canvas tab with every section
rendering, and idle CPU is 0% when animation is off or the page is hidden.
