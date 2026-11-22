# Parameterless `App.run()`, `App.withRootWidget()`, and Stack Cleanup

Refactor `App.run()` to take no parameters so applications can push controllers
in any order onto `app.ui`, add `App.withRootWidget(Widget)` as a shortcut for
`app.ui.mainWindow().rootWidget = ...`, and automatically pop all remaining
controllers in LIFO order when `UiSystemImpl.mainEventLoop()` exits.

## Target Lifecycle Flow

```
Caller (guidemo / yvidtrim / helloworld)
  |
  +-> app.withRootWidget(view.rootWidget())
  +-> app.ui.pushController(c1) --> c1.onPush()
  +-> app.ui.pushController(c2) --> c2.onPush()
  +-> app.run()
        +-> UiSystemImpl.mainEventLoop()
              +-> pushController(sysCtrl)
              +-> event loop steps ...
              +-> scope (exit): while (getActiveControllerOrNull() !is null)
                    +-> popController() (LIFO: sysCtrl, c2, c1)
                          +-> timerService.stopTimersForOwner(active)
                          +-> controllers.pop() --> active.onPop()
```

## Phases

- Phase 1: [app-run-ph01.md](app-run-ph01.md)
  - Add `App.withRootWidget(Widget root)`, `@disable this();`, and `invariant`
    in `yguilib/source/yguilib/app.d`.
  - Update `UiSystemImpl.mainEventLoop()` in
    `yguilib/source/yguilib/internal/uisystem_impl.d` to pop all remaining
    controllers on `scope (exit)` in LIFO order and add a unit test verifying
    `onPop()` order and timer cleanup.
- Phase 2: [app-run-ph02.md](app-run-ph02.md)
  - Change `App.run()` in `yguilib/source/yguilib/app.d` to parameterless
    `void run()`.
  - Migrate all callers (`guidemoapp.d`, `yvidtrim/app.d`,
    `helloworld/app.d`, `virtlist.d`, `button_controller.d`,
    `virtlist_controller.d`) to `app.withRootWidget(...)` and parameterless
    `app.run()`.
  - Update `AGENTS.md` and remove the completed first item from `TODO.md`.
