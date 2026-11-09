module yguilib.widget.scroll_components;

import yguilib.events : AppEvent;
import yguilib.render.render_types : PointF;
import yguilib.widget.component : WidgetComponent;

/// Component enabling a widget to scroll its first child inside its clipped
/// content area.
final class ScrollableArea : WidgetComponent {
  /// Packed payload stored in `AppEvent.ViewData.value` when
  /// `scrollChangedEvent` is emitted.
  union AppEventViewValue {
    ulong[AppEvent.ViewData.valueSize] raw;
    struct {
      /// Size of the first child widget after layout.
      PointF contentSize;
      /// Size of the scrollable widget's content area after layout.
      PointF viewportSize;
      /// Effective scroll offset applied to the first child.
      PointF offset;
    }

    alias raw this;

    this(in ulong[AppEvent.ViewData.valueSize] raw) {
      this.raw = raw;
    }

    this(PointF contentSize, PointF viewportSize, PointF offset) {
      this.raw = 0;
      this.contentSize = contentSize;
      this.viewportSize = viewportSize;
      this.offset = offset;
    }
  }

  static assert(
    AppEventViewValue.sizeof ==
      (ulong[AppEvent.ViewData.valueSize]).sizeof
  );

  this() {}

  this(PointF offset, string scrollChangedEvent = null) {
    this.offset = offset;
    this.scrollChangedEvent = scrollChangedEvent;
  }

  ScrollableArea withOffset(PointF newOffset) {
    this.offset = newOffset;
    return this;
  }

  ScrollableArea withOffset(float x, float y) {
    this.offset = PointF(x, y);
    return this;
  }

  ScrollableArea withClampOffset(bool clamp) {
    this.clampOffset = clamp;
    return this;
  }

  ScrollableArea withScrollChangedEvent(string eventName) {
    this.scrollChangedEvent = eventName;
    return this;
  }

  /// Last computed size of the first child widget.
  @property PointF contentSize() const nothrow @safe {
    return fContentSize;
  }

  /// Last computed size of the scrollable widget's content area.
  @property PointF viewportSize() const nothrow @safe {
    return fViewportSize;
  }

  /// Scroll offset in logical points (`childPos = contentOrigin - offset`).
  PointF offset = PointF(0.0f, 0.0f);

  /// When true, `ScrollSystem` clamps `offset` to
  /// `[0, max(0, contentSize - viewportSize)]` during layout.
  bool clampOffset = true;

  /// Optional view event name emitted in `postLayout` when `contentSize`,
  /// `viewportSize`, or `offset` changes.
  string scrollChangedEvent;

package(yguilib):
  PointF fContentSize = PointF(0.0f, 0.0f);
  PointF fViewportSize = PointF(0.0f, 0.0f);
  PointF fLastEmittedContentSize = PointF(-1.0f, -1.0f);
  PointF fLastEmittedViewportSize = PointF(-1.0f, -1.0f);
  PointF fLastEmittedOffset = PointF(-1.0f, -1.0f);
}

unittest {
  auto sa = new ScrollableArea(PointF(10, 20), "scrollChange");
  assert(sa.offset == PointF(10, 20));
  assert(sa.scrollChangedEvent == "scrollChange");
  assert(sa.clampOffset);

  sa.withOffset(PointF(30, 40)).withClampOffset(false);
  assert(sa.offset == PointF(30, 40));
  assert(!sa.clampOffset);

  ScrollableArea.AppEventViewValue val = ScrollableArea.AppEventViewValue(
    PointF(500, 300),
    PointF(200, 150),
    PointF(30, 40)
  );
  assert(val.contentSize == PointF(500, 300));
  assert(val.viewportSize == PointF(200, 150));
  assert(val.offset == PointF(30, 40));

  ScrollableArea.AppEventViewValue unpacked =
    ScrollableArea.AppEventViewValue(val.raw);
  assert(unpacked.contentSize == PointF(500, 300));
  assert(unpacked.viewportSize == PointF(200, 150));
  assert(unpacked.offset == PointF(30, 40));
}
