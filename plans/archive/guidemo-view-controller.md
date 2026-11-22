# View-Controller Separation in `source/guidemo`

Overview of the view-controller separation for `source/guidemo` (first item
in `TODO.md`). `ModelTracker!DemoModel`, `ModelTracker!TabsModel`, and
`DemoView` are constructed before `DemoController`, and `DemoController`
receives a `DemoControllerParams` struct rather than creating `DemoView`
internally. Each `Page` view is also constructed before its `*PageController`.

## Target Architecture

```
+----------------------------------------------------------------------------+
|                          guidemo.guidemoapp.main                           |
|                                                                            |
|  1. demoTracker = ModelTracker!DemoModel(new DemoModel())                  |
|  2. tabsTracker = ModelTracker!TabsModel(createHeaderTabsModel())          |
|  3. demoView = new DemoView(app.ui, demoTracker, tabsTracker)              |
|  4. rootWidget = demoView.getRootWidget()                                  |
|  5. app.ui.mainWindow().rootWidget = rootWidget                            |
|  6. params = DemoControllerParams().withUi(app.ui)...                      |
|  7. demoController = new DemoController(params)                            |
|  8. Create each *Page before its *PageController                           |
+---------------------+----------------------------------+-------------------+
                      |                                  |
                      v                                  v
       +------------------------------+   +------------------------------+
       |          DemoView            |   |        DemoController        |
       |   (source/guidemo/view.d)    |   | (source/guidemo/controller.d)|
       |                              |   |                              |
       | - ModelTracker.from(demo)    |   | - this(ref DemoController-   |
       | - ModelTracker.from(tabs)    |   |     Params params)           |
       | - builds header & status bar |   | - holds DemoView reference   |
       | - update() / getRootWidget() |   | - headless UiSystemImpl test |
       +------------------------------+   +------------------------------+
```

## Phases

- Phase 1: [guidemo-view-controller-ph01.md](guidemo-view-controller-ph01.md)
  - Update `DemoView` (`source/guidemo/view.d`) with `@disable this()`,
    non-null `UiSystem ui` first parameter, `invariant`, and headless
    `UiSystemImpl(null)` unit test.
  - Remove `createWithParent` and add `@disable this()` across the 6 page
    controllers in `source/guidemo/pages/*_controller.d`.
- Phase 2: [guidemo-view-controller-ph02.md](guidemo-view-controller-ph02.md)
  - Add `DemoControllerParams` and refactor `DemoController`
    (`source/guidemo/controller.d`) with headless `UiSystemImpl(null)` test.
  - Update `source/guidemo/guidemoapp.d` to wire trackers, `DemoView`,
    `DemoController`, and all 6 page views before their controllers.
  - Update `TODO.md` to remove the completed first item.
