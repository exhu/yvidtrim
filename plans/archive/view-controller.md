# View-Controller Separation in `source/yvidtrim`

Overview of the view-controller separation for `source/yvidtrim` (first item
in `TODO.md`). `ModelTracker!MainModel` and `MainView` are constructed before
`MainController`, and `MainController` receives both `ModelTracker!MainModel`
and `MainView` rather than creating `MainView` internally.

## Target Architecture

```
+-----------------------------------------------------------------------+
|                           yvidtrim.app.main                           |
|                                                                       |
|  1. app = App.makeAppWithTitleWh("yvidtrim", 1280, 720)               |
|  2. tracker = ModelTracker!MainModel(new MainModel())                 |
|  3. view = new MainView(app.ui, tracker)                              |
|  4. app.ui.mainWindow().rootWidget = view.rootWidget()                |
|  5. controller = new MainController(app.ui, tracker, view)            |
|  6. app.run(controller)                                               |
+-------------------+-------------------------------+-------------------+
                    |                               |
                    v                               v
     +------------------------------+  +------------------------------+
     |         MainView             |  |       MainController         |
     | (source/yvidtrim/view.d)     |  | (source/yvidtrim/controller.d|
     |                              |  |                              |
     | - ModelTracker.from(tracker) |  | - ModelTracker.from(tracker) |
     | - makeMainViewWidgets(ui)    |  | - holds MainView reference   |
     | - update() mutates widgets   |  | - handleEvent / update /     |
     | - rootWidget()               |  |   updateView                 |
     +------------------------------+  +------------------------------+
```

## Phases

- Phase 1: [view-controller-ph01.md](view-controller-ph01.md) — Extract
  `MainModel` (`source/yvidtrim/model.d`), `MainView` (`source/yvidtrim/view.d`
  with headless `unittest`), and `source/yvidtrim/test_main.d`.
- Phase 2: [view-controller-ph02.md](view-controller-ph02.md) — Extract
  `MainController` (`source/yvidtrim/controller.d` with headless `unittest`),
  refactor `source/yvidtrim/app.d`, wire `yvidtrim_test` in `meson.build`,
  and update `ARCHITECTURE.md` and `TODO.md`.
