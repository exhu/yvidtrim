module yguilib.widget.internal.scroll_system;

package(yguilib):

import std.algorithm.comparison : max;
import std.math.traits : isFinite;
import yguilib.events.builder : ViewAppEventBuilder;
import yguilib.render.render_types : PointF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.scroll_components : ScrollableArea;
import yguilib.widget.system : SystemPhase, WidgetSystem,
  WidgetSystemContext, WidgetSystemHost;
import yguilib.widget.visible : VisibleWidget;
import yguilib.widget.widget_view : passViewEvent;

final class ScrollSystem : WidgetSystem {
  /// Constructs ScrollSystem. `host` is allowed to be null in isolated tests.
  this(WidgetSystemHost host = null) nothrow @safe {
    super(scrollSystemPriority);
    this.host = host;
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.layout | SystemPhase.postLayout;
  }

  override void onRegister(WidgetSystemHost newHost) {
    if (newHost !is null) {
      host = newHost;
    }
  }

  override void layout(ref WidgetSystemContext ctx) {
    if (ctx.root is null || !ctx.root.visible ||
        ctx.unclippedWidgets.length == 0) {
      return;
    }

    foreach (ref vw; ctx.unclippedWidgets) {
      Widget w = vw.widget;
      if (w is null || w.components.scrollableArea is null) {
        continue;
      }
      handleScrollLayout(w);
    }
  }

  override void postLayout(ref WidgetSystemContext ctx) {
    if (ctx.root is null || !ctx.root.visible ||
        ctx.unclippedWidgets.length == 0) {
      return;
    }

    WidgetSystemHost activeHost = ctx.host !is null ? ctx.host : host;
    foreach (ref vw; ctx.unclippedWidgets) {
      Widget w = vw.widget;
      if (w is null || w.components.scrollableArea is null) {
        continue;
      }
      handleScrollPostLayout(w, activeHost);
    }
  }

private:
  static void handleScrollLayout(Widget w) {
    ScrollableArea sa = w.components.scrollableArea;
    assert(sa !is null);

    w.clipChildren = true;
    const RectF contentArea = w.getContentArea();
    sa.fViewportSize = PointF(contentArea.width, contentArea.height);

    Widget child = findFirstScrollChild(w);
    if (child !is null) {
      sa.fContentSize = PointF(child.rect.width, child.rect.height);

      if (sa.clampOffset) {
        const float maxScrollX = max(
          0.0f,
          sa.fContentSize.x - sa.fViewportSize.x
        );
        const float maxScrollY = max(
          0.0f,
          sa.fContentSize.y - sa.fViewportSize.y
        );

        if (!isFinite(sa.offset.x) || sa.offset.x < 0.0f) {
          sa.offset.x = 0.0f;
        } else if (sa.offset.x > maxScrollX) {
          sa.offset.x = maxScrollX;
        }

        if (!isFinite(sa.offset.y) || sa.offset.y < 0.0f) {
          sa.offset.y = 0.0f;
        } else if (sa.offset.y > maxScrollY) {
          sa.offset.y = maxScrollY;
        }
      }

      child.rect.x = contentArea.x - sa.offset.x;
      child.rect.y = contentArea.y - sa.offset.y;
    } else {
      sa.fContentSize = PointF(0.0f, 0.0f);
      if (sa.clampOffset) {
        sa.offset = PointF(0.0f, 0.0f);
      }
    }
  }

  static void handleScrollPostLayout(Widget w, WidgetSystemHost activeHost) {
    ScrollableArea sa = w.components.scrollableArea;
    assert(sa !is null);

    const bool changed = (sa.fContentSize != sa.fLastEmittedContentSize ||
      sa.fViewportSize != sa.fLastEmittedViewportSize ||
      sa.offset != sa.fLastEmittedOffset);

    sa.fLastEmittedContentSize = sa.fContentSize;
    sa.fLastEmittedViewportSize = sa.fViewportSize;
    sa.fLastEmittedOffset = sa.offset;

    if (changed && sa.scrollChangedEvent.length > 0 && activeHost !is null) {
      auto val = ScrollableArea.AppEventViewValue(
        sa.fContentSize,
        sa.fViewportSize,
        sa.offset
      );
      auto ev = ViewAppEventBuilder(sa.scrollChangedEvent)
        .widget(w)
        .value(val)
        .build();
      passViewEvent(activeHost, w, ev);
    }
  }

  static Widget findFirstScrollChild(Widget w) {
    foreach (child; w.children) {
      if (child.visible && child.components.anchor is null) {
        return child;
      }
    }
    return null;
  }

  WidgetSystemHost host;
}

version (unittest) {
  import yguilib.events : AppEvent;
  import yguilib.object_registry : ObjectRegistry;
  import yguilib.widget.layout_components : Insets, Size;
  import yguilib.widget.widget_view : WidgetView, WidgetViewController;

  private final class TestScrollHost : WidgetSystemHost {
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
}

unittest {
  auto host = new TestScrollHost();
  auto scrollSys = new ScrollSystem(host);
  assert(scrollSys.priority == WidgetSystem.scrollSystemPriority);
  assert(
    scrollSys.phases == (SystemPhase.layout | SystemPhase.postLayout)
  );

  auto parent = new Widget(1);
  parent.rect = RectF(0, 0, 100, 100);
  auto sa = new ScrollableArea(PointF(10, 20), "onScroll");
  parent.components.scrollableArea = sa;

  auto child = new Widget(2);
  child.rect = RectF(0, 0, 250, 150);
  parent.addChild(child);

  VisibleWidget[] unclipped = [
    VisibleWidget(parent, RectF(0, 0, 100, 100)),
    VisibleWidget(child, RectF(0, 0, 250, 150)),
  ];

  WidgetSystemContext ctx;
  ctx.host = host;
  ctx.root = parent;
  ctx.unclippedWidgets = unclipped;

  // Layout phase: verifies child placement and clamping
  scrollSys.layout(ctx);
  assert(parent.clipChildren);
  assert(sa.viewportSize == PointF(100, 100));
  assert(sa.contentSize == PointF(250, 150));
  assert(sa.offset == PointF(10, 20));
  assert(child.rect.x == -10.0f);
  assert(child.rect.y == -20.0f);

  // PostLayout phase: verifies view event emission
  scrollSys.postLayout(ctx);
  assert(host.sentEvents.length == 1);
  assert(host.sentEvents[0].view.eventName == "onScroll");
  assert(host.sentEvents[0].view.widget is parent);
  auto unpacked = ScrollableArea.AppEventViewValue(
    host.sentEvents[0].view.value
  );
  assert(unpacked.contentSize == PointF(250, 150));
  assert(unpacked.viewportSize == PointF(100, 100));
  assert(unpacked.offset == PointF(10, 20));

  // Second postLayout without changes: no duplicate event
  host.sentEvents = null;
  scrollSys.postLayout(ctx);
  assert(host.sentEvents.length == 0);

  // Test offset clamping beyond max: contentSize 250, viewport 100 -> max 150
  sa.offset = PointF(300, 200);
  scrollSys.layout(ctx);
  assert(sa.offset == PointF(150, 50));
  assert(child.rect.x == -150.0f);
  assert(child.rect.y == -50.0f);

  scrollSys.postLayout(ctx);
  assert(host.sentEvents.length == 1);
  unpacked = ScrollableArea.AppEventViewValue(host.sentEvents[0].view.value);
  assert(unpacked.offset == PointF(150, 50));

  // Test negative offset clamped to 0
  host.sentEvents = null;
  sa.offset = PointF(-25, -10);
  scrollSys.layout(ctx);
  assert(sa.offset == PointF(0, 0));
  assert(child.rect.x == 0.0f);
  assert(child.rect.y == 0.0f);

  // Test unconstrained offset when clampOffset = false
  sa.clampOffset = false;
  sa.offset = PointF(-20, 500);
  scrollSys.layout(ctx);
  assert(sa.offset == PointF(-20, 500));
  assert(child.rect.x == 20.0f);
  assert(child.rect.y == -500.0f);

  // Test padding offsets viewport origin
  sa.clampOffset = true;
  sa.offset = PointF(10, 10);
  parent.components.size = new Size();
  // top, right, bottom, left
  parent.components.size.padding = Insets(5, 5, 5, 5);
  scrollSys.layout(ctx);
  assert(sa.viewportSize == PointF(90, 90));
  assert(child.rect.x == -5.0f); // contentArea.x (5) - offset.x (10)
  assert(child.rect.y == -5.0f); // contentArea.y (5) - offset.y (10)
}
