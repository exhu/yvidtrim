# Phase 1: `App.withRootWidget()` and `mainEventLoop()` LIFO Stack Cleanup

Add `App.withRootWidget(Widget root)` in `yguilib/source/yguilib/app.d` and
update `UiSystemImpl.mainEventLoop()` in
`yguilib/source/yguilib/internal/uisystem_impl.d` so all controllers remaining
on `ControllerStack` are popped in LIFO order when the event loop exits.

## Steps

1. Update `yguilib/source/yguilib/app.d`:
   - Import `yguilib.widget : Widget;`.
   - Add `@disable this();` and `invariant { assert(fUi !is null); }` to `App`.
   - Add `withRootWidget`:
     ```d
     /// Sets the main window's root widget and returns `this` for chaining.
     App withRootWidget(Widget root) {
       assert(root !is null, "root must not be null");
       fUi.mainWindow().rootWidget = root;
       return this;
     }
     ```
2. Update `yguilib/source/yguilib/internal/uisystem_impl.d`:
   - In `mainEventLoop()`, replace the `scope (exit)` block after
     `pushController(sysCtrl);` with a loop that pops all remaining controllers
     in LIFO order:
     ```d
     auto sysCtrl = new UiSystemController(this, pipeline);
     pushController(sysCtrl);
     scope (exit) {
       while (getActiveControllerOrNull() !is null) {
         popController();
       }
     }
     ```
   - Add a `unittest` verifying that when multiple controllers with active
     timers are pushed before `mainEventLoop()`, exiting `mainEventLoop()` pops
     all of them in LIFO order (recording `onPop` in reverse push order) and
     stops all of their timers (`!ui.isTimerActive(...)`).

## Verification

```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
```
