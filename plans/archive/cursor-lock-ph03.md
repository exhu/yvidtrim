# Cursor Lock Phase 3: guidemo knob page, docs, TODO

Read AGENTS.md and codestyle.md first. Phase 2 added
`enum CursorCapture { none, capture, lock }` in
`yguilib/source/yguilib/widget/input_components.d` and
`WidgetBuilder.onMouseDrag(string, CursorCapture)`. With `lock`, the
cursor is hidden while pressed and mouseDrag events carry deltas in
`MouseEvent.AppEventViewValue.relX/relY`.

## Steps
1. New guidemo page following the scrollbars page/controller pattern
   (`source/guidemo/pages/scrollbars_page.d`, `scrollbars_controller.d`,
   model `ScrollbarsPageModel` in `source/guidemo/model.d`):
   - `DemoPage.knob` in `source/guidemo/model.d` enum + `demoPages` meta
     ("Knob (Lock)", "Knob"); `KnobPageModel : VersionedModel` with
     `float value` (and `bool dragging`).
   - `source/guidemo/pages/knob_page.d`: View with a "drag value" box:
     a widget with background/border and TextLabel showing the value
     formatted `%.2f`, wired with `onMouseDown`, `onMouseDrag(ev,
     CursorCapture.lock)`, `onMouseUp`; a help label explaining: drag
     horizontally, cursor hidden, unbounded, cursor returns on release;
     vertical drag ignored. View updates label from the model.
   - `source/guidemo/pages/knob_controller.d`: `DefaultController`
     subclass; on drag event: `value += relX * 0.01f` (hold Shift? no --
     keep simple), mark model changed; other events ->
     `return super.handleEvent(ev)`. ModelTracker created before View and
     Controller, passed explicitly (see AGENTS.md View-Controller
     Separation).
   - Register in `source/guidemo/guidemoapp.d` (like scrollPage ~line 163)
     and add both files to root `meson.build` source list and test
     target(s) (check how scrollbars_* files are listed).
   - Headless unittest in knob_controller.d: send synthetic drag view
     events (see scrollbars_controller.d unittests ~line 150) and assert
     the value changes by relX * sensitivity.
2. ARCHITECTURE.md: document input cursor modes (none/capture/lock) in
   the input system section; keep file under 250 lines; mention new page.
3. TODO.md: remove the first item (lines 1-2: "already implemented?
   mouse capture component ... knobs").
4. `ninja -C _build && meson test -C _build`; all must pass.
