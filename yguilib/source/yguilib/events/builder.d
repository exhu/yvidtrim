module yguilib.events.builder;

import yguilib.events : AppEvent;
import yguilib.widget : Widget;

/// Builder for constructing view `AppEvent` instances with `ViewData` payloads.
struct ViewAppEventBuilder {
  /// Constructs a builder with a pre-configured event name.
  this(string eventName) {
    viewData.eventName = eventName;
  }

  /// Constructs a builder with an event name and originating widget.
  ///
  /// Params:
  ///   eventName = Logical name of the view event.
  ///   widget = Originating widget (allowed to be null).
  this(string eventName, Widget widget) {
    viewData.eventName = eventName;
    viewData.widget = widget;
  }

  /// Sets the event name.
  ref ViewAppEventBuilder eventName(string name) return {
    viewData.eventName = name;
    return this;
  }

  /// Sets the originating widget.
  ///
  /// Params:
  ///   w = Originating widget. Allowed to be null.
  ref ViewAppEventBuilder widget(Widget w) return {
    viewData.widget = w;
    return this;
  }

  /// Sets the nearest view widget ancestor.
  ///
  /// Params:
  ///   vw = Nearest view widget ancestor. Allowed to be null.
  ref ViewAppEventBuilder viewWidget(Widget vw) return {
    viewData.viewWidget = vw;
    return this;
  }

  /// Sets the primary value in the opaque payload array and zeroes the rest.
  ref ViewAppEventBuilder value(ulong val) return {
    viewData.value = 0;
    viewData.value[0] = val;
    return this;
  }

  /// Sets the full opaque payload array.
  ref ViewAppEventBuilder value(
    in ulong[AppEvent.ViewData.valueSize] val
  ) return {
    viewData.value = val;
    return this;
  }

  /// Sets the custom user payload object and optional release delegate.
  ///
  /// Params:
  ///   obj = Custom payload object. Allowed to be null.
  ///   release = Optional cleanup delegate called on event destruction.
  ///             Allowed to be null.
  ref ViewAppEventBuilder data(
    Object obj,
    void delegate(in AppEvent.ViewData) release = null
  ) return {
    viewData.data = obj;
    viewData.releaseData = release;
    return this;
  }

  /// Sets the release delegate for custom payload cleanup.
  ///
  /// Params:
  ///   release = Cleanup delegate called on event destruction.
  ///             Allowed to be null.
  ref ViewAppEventBuilder releaseData(
    void delegate(in AppEvent.ViewData) release
  ) return {
    viewData.releaseData = release;
    return this;
  }

  /// Builds and returns the configured AppEvent.
  AppEvent build() {
    return AppEvent(viewData);
  }

private:
  AppEvent.ViewData viewData;
}

unittest {
  import yguilib.render.render_types : RectF;

  auto parent = new Widget(null, RectF(0, 0, 100, 100));
  auto child = new Widget(parent, RectF(10, 10, 50, 50));

  // Test 1: Full fluent configuration starting from empty builder
  auto ev1 = ViewAppEventBuilder()
    .eventName("buttonClick")
    .widget(child)
    .viewWidget(parent)
    .value(42)
    .build();

  assert(ev1.kind == AppEvent.Kind.view);
  assert(ev1.view.eventName == "buttonClick");
  assert(ev1.view.widget is child);
  assert(ev1.view.viewWidget is parent);
  assert(ev1.view.value[0] == 42);
  assert(ev1.view.data is null);
  assert(ev1.view.releaseData is null);

  // Test 2: Parameterized constructor (eventName only)
  auto ev2 = ViewAppEventBuilder("menuAction")
    .widget(child)
    .value(1)
    .build();

  assert(ev2.kind == AppEvent.Kind.view);
  assert(ev2.view.eventName == "menuAction");
  assert(ev2.view.widget is child);
  assert(ev2.view.viewWidget is null);
  assert(ev2.view.value[0] == 1);

  // Test 3: Parameterized constructor (eventName and widget)
  auto ev3 = ViewAppEventBuilder("itemSelected", child).build();
  assert(ev3.kind == AppEvent.Kind.view);
  assert(ev3.view.eventName == "itemSelected");
  assert(ev3.view.widget is child);
  assert(ev3.view.viewWidget is null);
  assert(ev3.view.value[0] == 0);

  // Test 4: Custom object payload with release delegate
  static class TestPayload {
    int id;
    this(int id) {
      this.id = id;
    }
  }

  bool released = false;
  ulong releasedVal = 0;
  {
    auto ev4 = ViewAppEventBuilder("withPayload")
      .data(new TestPayload(777), (in AppEvent.ViewData vd) {
        released = true;
        releasedVal = vd.value[0];
      })
      .value(99)
      .build();

    assert(ev4.view.data !is null);
    assert((cast(TestPayload)ev4.view.data).id == 777);
    assert(ev4.view.value[0] == 99);
    assert(!released);
  }
  assert(released);
  assert(releasedVal == 99);

  // Test 5: Separate releaseData setter
  bool separateReleased = false;
  {
    auto ev5 = ViewAppEventBuilder("separateRelease")
      .data(new TestPayload(888))
      .releaseData((in AppEvent.ViewData vd) {
        separateReleased = true;
      })
      .build();

    assert(ev5.view.data !is null);
    assert(!separateReleased);
  }
  assert(separateReleased);

  // Test 6: Setting full value array
  ulong[AppEvent.ViewData.valueSize] fullVal = [10, 20, 30, 40];
  auto ev6 = ViewAppEventBuilder("fullVal")
    .value(fullVal)
    .build();
  assert(ev6.view.value == fullVal);
}
