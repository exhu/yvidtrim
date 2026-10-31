module yguilib.widget.system;

import yguilib.events : AppEvent;
import yguilib.render : Renderer;
import yguilib.uisystem : EventControl;
import yguilib.widget : Widget;
import yguilib.widget.visible : VisibleWidget, VisibleWidgets;
import yguilib.window : Window;

/// Narrow host interface providing UI-system services needed by WidgetSystems.
/// Exposes `sendAppEvent` via `EventControl`.
interface WidgetSystemHost : EventControl {
}

/// Flags indicating which pipeline phases a WidgetSystem participates in.
enum SystemPhase : uint {
  none       = 0,
  event      = 1 << 0,
  preLayout  = 1 << 1,
  layout     = 1 << 2,
  postLayout = 1 << 3,
  render     = 1 << 4,
}

/// Result of handling an AppEvent in a WidgetSystem.
struct SystemEventResult {
  bool consumed;
  bool requestUpdateView;
  int timeoutMs = -1;
}

/// Shared per-window context passed to WidgetSystem lifecycle methods.
struct WidgetSystemContext {
  /// Host interface; allowed to be null in isolated unit tests.
  WidgetSystemHost host;
  /// Target window; allowed to be null in headless unit tests.
  Window window;
  /// Root widget of the window's widget tree; allowed to be null when empty.
  Widget root;
  /// Window renderer; allowed to be null in layout/input unit tests.
  Renderer renderer;
  /// Visible widgets collected with parent clipping (for event, postLayout,
  /// and render phases).
  VisibleWidgets visibleWidgets;
  /// Visible widgets collected without parent clipping (for layout phase).
  VisibleWidgets unclippedWidgets;
}

/// Base class for all internal and user-defined systems that process
/// the Widget tree.
abstract class WidgetSystem {
  /// Priority constant for FocusSystem (runs before InputSystem in event
  /// phase).
  enum int focusSystemPriority = -100;
  /// Priority constant for InputSystem.
  enum int inputSystemPriority = 0;
  /// Priority constant for LayoutSystem.
  enum int layoutSystemPriority = 0;
  /// Priority constant for WidgetPainterSystem.
  enum int painterSystemPriority = 0;
  /// Default priority for user-defined systems when not specified.
  enum int defaultPriority = 0;

  /// Constructs a WidgetSystem with the given execution priority.
  /// Lower priority values run earlier within the same phase.
  this(int priority = defaultPriority) nothrow @safe {
    fPriority = priority;
  }

  /// Read-only priority within a phase (lower runs earlier).
  @property int priority() const nothrow @safe {
    return fPriority;
  }

  /// Bitmask of SystemPhase values this system is active in.
  @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.none;
  }

  /// Desired event loop timeout in milliseconds (< 0 = infinite/idle).
  @property int timeoutMs() const nothrow @safe {
    return -1;
  }

  /// Called once when the system is registered with the pipeline.
  /// `host` is allowed to be null in isolated tests.
  void onRegister(WidgetSystemHost host) {}

  /// Called once when the system is unregistered from the pipeline.
  void onUnregister() {}

  /// Called when a window is closed/removed so systems with per-window state
  /// can clean up entries keyed by `window` or `window.id`.
  void onWindowClosed(Window window) {}

  /// Phase 1: Handle incoming AppEvent.
  SystemEventResult handleEvent(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    return SystemEventResult(false, false);
  }

  /// Phase 2: Pre-layout update (animations, bindings, state sync).
  void preLayout(ref WidgetSystemContext ctx) {}

  /// Phase 3: Layout calculation (sizing and positioning).
  void layout(ref WidgetSystemContext ctx) {}

  /// Phase 4: Post-layout reaction (hover refresh, spatial indexing).
  void postLayout(ref WidgetSystemContext ctx) {}

  /// Phase 5: Rendering (drawing widgets, overlays, diagnostics).
  void render(ref WidgetSystemContext ctx) {}

protected:
  /// Helper: Root-to-leaf (back-to-front) iteration over a widget list.
  static void traverseRootToLeaf(alias Fn)(VisibleWidgets widgets) {
    foreach (ref vw; widgets) {
      Fn(vw);
    }
  }

  /// Helper: Leaf-to-root (front-to-back) iteration over a widget list.
  static void traverseLeafToRoot(alias Fn)(VisibleWidgets widgets) {
    foreach_reverse (ref vw; widgets) {
      Fn(vw);
    }
  }

private:
  int fPriority = defaultPriority;
}

/// Convenience base class for systems that perform a bottom-up (leaf-to-root)
/// pass followed by a top-down (root-to-leaf) pass over `VisibleWidgets`.
abstract class TwoPassWidgetSystem : WidgetSystem {
  this(int priority = defaultPriority) nothrow @safe {
    super(priority);
  }

  void beginPass(ref WidgetSystemContext ctx) {}
  void processLeafToRoot(ref VisibleWidget vw, ref WidgetSystemContext ctx) {}
  void processRootToLeaf(ref VisibleWidget vw, ref WidgetSystemContext ctx) {}
  void endPass(ref WidgetSystemContext ctx) {}

protected:
  final void runTwoPass(
    VisibleWidgets widgets,
    ref WidgetSystemContext ctx
  ) {
    beginPass(ctx);
    foreach_reverse (ref vw; widgets) {
      processLeafToRoot(vw, ctx);
    }
    foreach (ref vw; widgets) {
      processRootToLeaf(vw, ctx);
    }
    endPass(ctx);
  }
}

// Verifies WidgetSystem default priorities and lifecycle no-op defaults.
unittest {
  final class TestSystem : WidgetSystem {
    this(int priority = defaultPriority) nothrow @safe {
      super(priority);
    }
  }

  assert(WidgetSystem.focusSystemPriority == -100);
  assert(WidgetSystem.inputSystemPriority == 0);
  assert(WidgetSystem.layoutSystemPriority == 0);
  assert(WidgetSystem.painterSystemPriority == 0);
  assert(WidgetSystem.defaultPriority == 0);

  auto defSys = new TestSystem();
  assert(defSys.priority == 0);
  assert(defSys.phases == SystemPhase.none);

  auto customSys = new TestSystem(42);
  assert(customSys.priority == 42);

  // Verify default lifecycle hooks do not throw or crash
  WidgetSystemContext ctx;
  AppEvent ev;
  customSys.onRegister(null);
  customSys.onWindowClosed(null);
  auto res = customSys.handleEvent(ev, ctx);
  assert(!res.consumed && !res.requestUpdateView);
  customSys.preLayout(ctx);
  customSys.layout(ctx);
  customSys.postLayout(ctx);
  customSys.render(ctx);
  customSys.onUnregister();
}

// Verifies traverseRootToLeaf and traverseLeafToRoot visitation order.
unittest {
  import yguilib.render.render_types : RectF;

  static int[] order;

  final class OrderTestSystem : WidgetSystem {
    void testTraversals(VisibleWidgets widgets) {
      order = [];
      traverseRootToLeaf!((ref VisibleWidget vw) {
        order ~= cast(int) vw.absRect.x;
      })(widgets);
      assert(order == [1, 2, 3]);

      order = [];
      traverseLeafToRoot!((ref VisibleWidget vw) {
        order ~= cast(int) vw.absRect.x;
      })(widgets);
      assert(order == [3, 2, 1]);
    }
  }

  auto w1 = new Widget(null, RectF(1, 0, 10, 10));
  auto w2 = new Widget(null, RectF(2, 0, 10, 10));
  auto w3 = new Widget(null, RectF(3, 0, 10, 10));
  VisibleWidget[] list = [
    VisibleWidget(w1, RectF(1, 0, 10, 10), false, RectF.init),
    VisibleWidget(w2, RectF(2, 0, 10, 10), false, RectF.init),
    VisibleWidget(w3, RectF(3, 0, 10, 10), false, RectF.init),
  ];

  auto sys = new OrderTestSystem();
  sys.testTraversals(list);
}

// Verifies TwoPassWidgetSystem execution order.
unittest {
  import yguilib.render.render_types : RectF;

  final class TwoPassTestSystem : TwoPassWidgetSystem {
    string[] log;

    override void beginPass(ref WidgetSystemContext ctx) {
      log ~= "begin";
    }

    override void processLeafToRoot(
      ref VisibleWidget vw,
      ref WidgetSystemContext ctx
    ) {
      log ~= "leaf:" ~ vw.widget.name;
    }

    override void processRootToLeaf(
      ref VisibleWidget vw,
      ref WidgetSystemContext ctx
    ) {
      log ~= "root:" ~ vw.widget.name;
    }

    override void endPass(ref WidgetSystemContext ctx) {
      log ~= "end";
    }

    void execute(VisibleWidgets widgets, ref WidgetSystemContext ctx) {
      runTwoPass(widgets, ctx);
    }
  }

  auto a = new Widget(null, RectF(0, 0, 10, 10));
  a.name = "A";
  auto b = new Widget(null, RectF(0, 0, 10, 10));
  b.name = "B";
  VisibleWidget[] list = [
    VisibleWidget(a, RectF(0, 0, 10, 10), false, RectF.init),
    VisibleWidget(b, RectF(0, 0, 10, 10), false, RectF.init),
  ];

  WidgetSystemContext ctx;
  auto sys = new TwoPassTestSystem();
  sys.execute(list, ctx);

  assert(sys.log == ["begin", "leaf:B", "leaf:A", "root:A", "root:B", "end"]);
}
