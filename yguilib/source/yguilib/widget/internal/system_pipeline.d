module yguilib.widget.internal.system_pipeline;

package(yguilib):

import std.array : Appender;
import yguilib.events : AppEvent;
import yguilib.render : Renderer;
import yguilib.render.render_types : RectF;
import yguilib.widget : Widget;
import yguilib.widget.internal.collect_visible : VisibleWidgetsCollector;
import yguilib.widget.system : SystemEventResult, SystemPhase,
  WidgetSystem, WidgetSystemContext, WidgetSystemHost;
import yguilib.widget.visible : VisibleWidget, VisibleWidgets;
import yguilib.window : Window;

/// Orchestrates registered WidgetSystems across event, preLayout, layout,
/// postLayout, and render phases.
final class WidgetSystemPipeline {
  this(WidgetSystemHost host) {
    assert(host !is null);
    this.host = host;
    this.collector = new VisibleWidgetsCollector;
  }

  invariant {
    assert(host !is null);
    assert(collector !is null);
  }

  /// Registers a system, inserts it in priority order, and calls onRegister.
  void registerSystem(WidgetSystem system) {
    assert(system !is null);
    foreach (s; systems) {
      if (s is system) {
        return;
      }
    }
    insertSorted(systems, system);
    rebuildPhaseLists();
    system.onRegister(host);
  }

  /// Unregisters a system and calls onUnregister.
  void unregisterSystem(WidgetSystem system) {
    assert(system !is null);
    size_t removeIdx = systems.length;
    foreach (i, s; systems) {
      if (s is system) {
        removeIdx = i;
        break;
      }
    }
    if (removeIdx == systems.length) {
      return;
    }
    foreach (i; removeIdx .. systems.length - 1) {
      systems[i] = systems[i + 1];
    }
    systems = systems[0 .. $ - 1];
    rebuildPhaseLists();
    system.onUnregister();
  }

  /// Finds the first registered system of type T (or null if none).
  T findSystem(T : WidgetSystem)() {
    foreach (s; systems) {
      if (auto match = cast(T) s) {
        return match;
      }
    }
    return null;
  }

  /// Finds the first registered system matching `type` (or null if none).
  WidgetSystem findSystemByType(TypeInfo_Class type) {
    assert(type !is null);
    foreach (s; systems) {
      if (typeid(s) is type) {
        return s;
      }
    }
    return null;
  }

  // TODO call it when window is closed
  /// Notifies all registered systems that a window has closed.
  void notifyWindowClosed(Window window) {
    assert(window !is null);
    foreach (s; systems) {
      s.onWindowClosed(window);
    }
  }

  /// Notifies all registered systems that a widget is released, and purges
  /// cached visible widget references.
  void notifyWidgetReleased(Widget w) {
    if (w is null) {
      return;
    }
    import std.algorithm.mutation : remove;
    fLastVisibleWidgets = fLastVisibleWidgets.remove!(
      vw => vw.widget is w
    );
    collector.clearBuffer();
    foreach (s; systems) {
      s.onWidgetReleased(w);
    }
  }

  /// Returns the cached clipped visible widgets from the last layout pass.
  @property VisibleWidgets lastVisibleWidgets() {
    return fLastVisibleWidgets;
  }

  /// Returns the minimum non-negative timeout requested across registered
  /// systems, or -1 if no system requires a timeout.
  @property int timeoutMs() const nothrow @safe {
    int nextTimeout = -1;
    foreach (s; systems) {
      const int t = s.timeoutMs;
      if (t >= 0) {
        if (nextTimeout < 0 || t < nextTimeout) {
          nextTimeout = t;
        }
      }
    }
    return nextTimeout;
  }

  /// Dispatches an AppEvent through all SystemPhase.event systems in priority
  /// order. Stops early if a system sets `result.consumed = true`.
  /// Note: `window` is allowed to be null in headless unit tests.
  SystemEventResult handleEvent(in AppEvent event, Window window = null) {
    WidgetSystemContext ctx = makeContext(window);
    SystemEventResult aggregate;

    foreach (s; eventSystems) {
      const SystemEventResult res = s.handleEvent(event, ctx);
      if (res.requestUpdateView) {
        aggregate.requestUpdateView = true;
      }
      if (res.timeoutMs >= 0) {
        if (aggregate.timeoutMs < 0 || res.timeoutMs < aggregate.timeoutMs) {
          aggregate.timeoutMs = res.timeoutMs;
        }
      }
      if (res.consumed) {
        aggregate.consumed = true;
        break;
      }
    }
    return aggregate;
  }

  /// Runs preLayout, layout (if tree layout is dirty), postLayout, and render
  /// (if tree is dirty) for `window`, followed by `window.swapBuffers()` when
  /// a frame was rendered.
  void updateAndRender(Window window) {
    if (window is null) {
      return;
    }
    if (window.rootWidget !is null && window.renderer !is null) {
      if (!updateAndRenderTree(window)) {
        return;
      }
    }
    window.swapBuffers();
  }

private:
  WidgetSystemContext makeContext(Window window) {
    WidgetSystemContext ctx;
    ctx.host = host;
    ctx.window = window;
    if (window !is null) {
      ctx.root = window.rootWidget;
      ctx.renderer = window.renderer;
    }
    ctx.visibleWidgets = fLastVisibleWidgets;
    return ctx;
  }

  /// Runs preLayout, layout, postLayout, and render on `window.rootWidget` and
  /// `window.renderer` without calling `window.swapBuffers()`. Useful for unit
  /// testing. Returns true if the render phase was executed.
  bool updateAndRenderTree(Window window) {
    WidgetSystemContext ctx = makeContext(window);
    assert(ctx.root !is null);
    assert(ctx.renderer !is null);
    if (fLastVisibleWidgets.length == 0 || ctx.root.isTreeLayoutDirty()) {
      fLastVisibleWidgets = collector.collectVisible(
        ctx.root,
        ctx.renderer,
        false
      );
      ctx.visibleWidgets = fLastVisibleWidgets;
    }
    runPreLayoutPhase(ctx);
    runLayoutAndPostLayoutPhases(ctx);
    return runRenderPhase(ctx);
  }

  void runPreLayoutPhase(ref WidgetSystemContext ctx) {
    foreach (s; preLayoutSystems) {
      s.preLayout(ctx);
    }
  }

  void runLayoutAndPostLayoutPhases(ref WidgetSystemContext ctx) {
    if (!ctx.root.isTreeLayoutDirty() && fLastVisibleWidgets.length > 0) {
      return;
    }

    ctx.unclippedWidgets = collector.collectVisible(
      ctx.root,
      ctx.renderer,
      true
    );

    snapshotRects(ctx.unclippedWidgets);

    foreach (s; layoutSystems) {
      s.layout(ctx);
    }

    syncDirtyAfterLayout(ctx.root, ctx.unclippedWidgets);

    fLastVisibleWidgets = collector.collectVisible(
      ctx.root,
      ctx.renderer,
      false
    );
    ctx.visibleWidgets = fLastVisibleWidgets;

    foreach (s; postLayoutSystems) {
      s.postLayout(ctx);
    }
  }

  bool runRenderPhase(ref WidgetSystemContext ctx) {
    if (!ctx.root.isTreeDirty()) {
      return false;
    }

    foreach (s; renderSystems) {
      s.render(ctx);
    }

    clearDirtyAfterRender(ctx.root, ctx.visibleWidgets);
    return true;
  }

  void snapshotRects(VisibleWidgets widgets) {
    oldRectBuf.clear();
    foreach (ref vw; widgets) {
      oldRectBuf ~= vw.widget.rect;
    }
  }

  void syncDirtyAfterLayout(Widget root, VisibleWidgets unclipped) {
    const RectF[] oldRects = oldRectBuf[];
    foreach (size_t i, ref vw; unclipped) {
      if (i < oldRects.length && vw.widget.rect != oldRects[i]) {
        vw.widget.dirty = true;
      }
      vw.widget.layoutDirty = false;
    }
    clearTreeLayoutDirty(root);
  }

  static void clearTreeLayoutDirty(Widget w) {
    if (w is null || !w.visible) {
      return;
    }
    w.layoutDirty = false;
    foreach (child; w.children) {
      clearTreeLayoutDirty(child);
    }
  }

  static void clearDirtyAfterRender(Widget root, VisibleWidgets visible) {
    foreach (ref vw; visible) {
      vw.widget.dirty = false;
    }
    clearTreeDirty(root);
  }

  static void clearTreeDirty(Widget w) {
    if (w is null || !w.visible) {
      return;
    }
    w.dirty = false;
    foreach (child; w.children) {
      clearTreeDirty(child);
    }
  }

  static void insertSorted(ref WidgetSystem[] list, WidgetSystem item) {
    size_t insertPos = list.length;
    foreach (i, existing; list) {
      if (item.priority < existing.priority) {
        insertPos = i;
        break;
      }
    }
    list ~= item;

    for (size_t i = list.length - 1; i > insertPos; --i) {
      list[i] = list[i - 1];
    }
    list[insertPos] = item;
  }

  void rebuildPhaseLists() {
    eventSystems = filterByPhase(SystemPhase.event);
    preLayoutSystems = filterByPhase(SystemPhase.preLayout);
    layoutSystems = filterByPhase(SystemPhase.layout);
    postLayoutSystems = filterByPhase(SystemPhase.postLayout);
    renderSystems = filterByPhase(SystemPhase.render);
  }

  WidgetSystem[] filterByPhase(SystemPhase phase) {
    WidgetSystem[] res;
    foreach (s; systems) {
      if ((s.phases & phase) != 0) {
        res ~= s;
      }
    }
    return res;
  }

  WidgetSystemHost host;
  VisibleWidgetsCollector collector;
  VisibleWidgets fLastVisibleWidgets;
  Appender!(RectF[]) oldRectBuf;

  WidgetSystem[] systems;
  // references to systems
  WidgetSystem[] eventSystems;
  WidgetSystem[] preLayoutSystems;
  WidgetSystem[] layoutSystems;
  WidgetSystem[] postLayoutSystems;
  WidgetSystem[] renderSystems;
}

version (unittest) {
private:
  import yguilib.object_registry : ObjectRegistry;
  import yguilib.widget.widget_view : WidgetView, WidgetViewController;

  class DummyHost : WidgetSystemHost {
    AppEvent[] sentEvents;
    ObjectRegistry!WidgetViewController dummyControllers;
    ObjectRegistry!WidgetView dummyViews;

    this() {
      dummyControllers = new ObjectRegistry!WidgetViewController();
      dummyViews = new ObjectRegistry!WidgetView();
    }

    override void sendAppEvent(AppEvent ev) {
      sentEvents ~= ev;
    }

    override @property
    ObjectRegistry!WidgetViewController widgetViewControllers() {
      return dummyControllers;
    }

    override @property ObjectRegistry!WidgetView widgetViews() {
      return dummyViews;
    }
  }

  static string[] executionLog;

  class PriorityTestSystem : WidgetSystem {
    string name;
    this(string name, int priority) nothrow @safe {
      super(priority);
      this.name = name;
    }

    override @property SystemPhase phases() const nothrow @safe {
      return SystemPhase.preLayout;
    }

    override void preLayout(ref WidgetSystemContext ctx) {
      executionLog ~= name;
    }
  }
}

// Verifies priority sorting, registration, lookup, and unregistration.
unittest {
  auto host = new DummyHost;
  auto pipeline = new WidgetSystemPipeline(host);

  auto s10 = new PriorityTestSystem("s10", 10);
  auto sFocus = new PriorityTestSystem(
    "sFocus",
    WidgetSystem.focusSystemPriority
  );
  auto s0 = new PriorityTestSystem("s0", 0);
  auto sNeg10 = new PriorityTestSystem("sNeg10", -10);

  pipeline.registerSystem(s10);
  pipeline.registerSystem(sFocus);
  pipeline.registerSystem(s0);
  pipeline.registerSystem(sNeg10);

  // findSystem
  assert(pipeline.findSystem!PriorityTestSystem() is sFocus);

  // Execution order
  executionLog = null;
  WidgetSystemContext ctx;
  ctx.host = host;
  pipeline.runPreLayoutPhase(ctx);
  assert(executionLog == ["sFocus", "sNeg10", "s0", "s10"]);

  // Unregister
  pipeline.unregisterSystem(sFocus);
  pipeline.unregisterSystem(s0);
  executionLog = null;
  pipeline.runPreLayoutPhase(ctx);
  assert(executionLog == ["sNeg10", "s10"]);
}

// Verifies event consumption and view update aggregation.
unittest {
  final class EvSys : WidgetSystem {
    bool consumed;
    bool requestUpdate;
    bool wasCalled;

    this(int priority, bool consumed, bool requestUpdate) nothrow @safe {
      super(priority);
      this.consumed = consumed;
      this.requestUpdate = requestUpdate;
    }

    override @property SystemPhase phases() const nothrow @safe {
      return SystemPhase.event;
    }

    override SystemEventResult handleEvent(
      in AppEvent event,
      ref WidgetSystemContext ctx
    ) {
      wasCalled = true;
      return SystemEventResult(consumed, requestUpdate);
    }
  }

  auto host = new DummyHost;
  auto pipeline = new WidgetSystemPipeline(host);

  auto e1 = new EvSys(-20, false, true);
  auto e2 = new EvSys(-10, true, false);
  auto e3 = new EvSys(0, false, false);

  pipeline.registerSystem(e1);
  pipeline.registerSystem(e2);
  pipeline.registerSystem(e3);

  AppEvent ev;
  auto res = pipeline.handleEvent(ev);
  assert(res.consumed);
  assert(res.requestUpdateView);
  assert(e1.wasCalled);
  assert(e2.wasCalled);
  assert(!e3.wasCalled); // stopped early because e2 consumed it
}

// Verifies full frame pipeline with core systems and dirty flag separation.
unittest {
  import yguilib.clibs.sdl3 : yguilib_sdl3_init, yguilib_sdl3_quit;
  import yguilib.render.render_types : ColorF;
  import yguilib.widget.drawing_components : Background;
  import yguilib.widget.internal.input_system : InputSystem;
  import yguilib.widget.internal.layout_system : LayoutSystem;
  import yguilib.widget.internal.widget_painter : WidgetPainterSystem;

  yguilib_sdl3_init();
  scope (exit) yguilib_sdl3_quit();

  auto win = new Window(320, 240, "test_pipeline");
  win.create();
  scope (exit) win.destroy();

  auto host = new DummyHost;
  auto pipeline = new WidgetSystemPipeline(host);

  auto layoutSys = new LayoutSystem();
  auto inputSys = new InputSystem(host);
  auto painterSys = new WidgetPainterSystem();

  static string[] phaseLog;
  static bool layoutRanWhileDirty;
  static bool renderRanWhileDirty;

  final class CustomPhaseSystem : WidgetSystem {
    this() nothrow @safe {
      super(100);
    }

    override @property SystemPhase phases() const nothrow @safe {
      return SystemPhase.preLayout | SystemPhase.layout |
        SystemPhase.postLayout | SystemPhase.render;
    }

    override void preLayout(ref WidgetSystemContext ctx) {
      phaseLog ~= "preLayout";
    }

    override void layout(ref WidgetSystemContext ctx) {
      phaseLog ~= "layout";
      if (ctx.root !is null) {
        layoutRanWhileDirty = ctx.root.isTreeLayoutDirty();
      }
    }

    override void postLayout(ref WidgetSystemContext ctx) {
      phaseLog ~= "postLayout";
    }

    override void render(ref WidgetSystemContext ctx) {
      phaseLog ~= "render";
      if (ctx.root !is null) {
        renderRanWhileDirty = ctx.root.isTreeDirty();
      }
    }
  }

  auto customSys = new CustomPhaseSystem();

  pipeline.registerSystem(layoutSys);
  pipeline.registerSystem(inputSys);
  pipeline.registerSystem(painterSys);
  pipeline.registerSystem(customSys);

  auto root = new Widget(1);
  root.rect = RectF(0, 0, 320, 240);
  root.components.background = new Background(ColorF(0.1f, 0.1f, 0.1f, 1.0f));
  auto child = new Widget(2);
  child.rect = RectF(10, 10, 100, 50);
  root.addChild(child);
  child.components.background = new Background(ColorF(1.0f, 0, 0, 1.0f));
  win.rootWidget = root;

  // Initial state: root and child are dirty and layoutDirty
  assert(root.isTreeLayoutDirty());
  assert(root.isTreeDirty());

  phaseLog = null;
  assert(pipeline.updateAndRenderTree(win));

  assert(phaseLog == ["preLayout", "layout", "postLayout", "render"]);
  assert(layoutRanWhileDirty);
  assert(renderRanWhileDirty);

  // After pipeline completes, dirty flags should be cleared
  assert(!root.isTreeLayoutDirty());
  assert(!root.isTreeDirty());
  assert(pipeline.lastVisibleWidgets.length == 2);

  // Subsequent call without invalidation should only run preLayout
  phaseLog = null;
  assert(!pipeline.updateAndRenderTree(win));
  assert(phaseLog == ["preLayout"]);

  // Toggling a hidden WidgetArray container to visible = true populates its
  // children during preLayout on the very first updateAndRenderTree pass.
  import yguilib.widget.data_components : WidgetArrayComponent,
    WidgetArrayProvider;
  import yguilib.widget.internal.data_system : DataSystem;

  final class SimpleArrayProvider : WidgetArrayProvider {
    uint nextId = 100;
    override void addWidget(Widget parent) {
      auto item = new Widget(nextId++);
      item.rect = RectF(0, 0, 40, 20);
      if (parent !is null) {
        parent.addChild(item);
      }
      item.components.background = new Background(ColorF(0, 1, 0, 1));
    }

    override void updateWidgetAt(Widget w, size_t index) {
    }
  }

  pipeline.registerSystem(new DataSystem());
  auto hiddenPage = new Widget(3);
  hiddenPage.rect = RectF(0, 60, 200, 100);
  root.addChild(hiddenPage);
  hiddenPage.setVisible(false);
  auto arrBox = new Widget(4);
  arrBox.rect = RectF(0, 0, 160, 30);
  hiddenPage.addChild(arrBox);
  auto arrComp = new WidgetArrayComponent();
  arrComp.provider = new SimpleArrayProvider();
  arrComp.itemsCount = 3;
  arrBox.components.widgetArray = arrComp;

  // Render while hiddenPage is invisible: arrBox is not populated yet
  assert(pipeline.updateAndRenderTree(win));
  assert(arrBox.children.length == 0);

  // Show hiddenPage: first pass must collect visible before preLayout so
  // DataSystem populates arrBox.children immediately
  hiddenPage.setVisible(true);
  assert(pipeline.updateAndRenderTree(win));
  assert(arrBox.children.length == 3);

  // Test ScrollSystem in full pipeline with off-screen child
  import yguilib.render.render_types : PointF;
  import yguilib.widget.internal.scroll_system : ScrollSystem;
  import yguilib.widget.scroll_components : ScrollableArea;

  pipeline.registerSystem(new ScrollSystem(host));
  auto scrollContainer = new Widget(5);
  scrollContainer.rect = RectF(0, 100, 100, 100);
  root.addChild(scrollContainer);
  auto scrollArea = new ScrollableArea()
    .withOffset(PointF(0, 0))
    .withScrollChangedEvent("pipelineScrolled");
  scrollContainer.components.scrollableArea = scrollArea;

  // Child larger than viewport and overflowing window bounds
  auto largeContent = new Widget(6);
  largeContent.rect = RectF(0, 0, 400, 300);
  scrollContainer.addChild(largeContent);
  largeContent.components.background = new Background(ColorF(0, 0, 1, 1));

  assert(pipeline.updateAndRenderTree(win));
  assert(scrollArea.viewportSize == PointF(100, 100));
  assert(scrollArea.contentSize == PointF(400, 300));
  assert(largeContent.rect.x == 0.0f);
  assert(largeContent.rect.y == 0.0f);

  // Scroll offset moves largeContent
  scrollContainer.setScrollOffset(PointF(50, 80));
  assert(pipeline.updateAndRenderTree(win));
  assert(largeContent.rect.x == -50.0f);
  assert(largeContent.rect.y == -80.0f);
}
