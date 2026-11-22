/**
 * button_support.d - Shared helpers for push-button style controls.
 *
 * Provides the common construction config, a fluent builder mixin, active
 * widget tracking, press/release hit tracking, and view-event emission used
 * by button WidgetSystems (e.g. `AnimatedHoverButtonSystem`).
 */
module yguilib.controls.internal.button_support;

import yguilib.allochelpers : ReusableArray;
import yguilib.controls.common : ButtonFace, WidgetColors,
  applyButtonFaceStyle, orDefault;
import yguilib.controls.tooltip : Tooltip;
import yguilib.events.builder : ViewAppEventBuilder;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget, isEffectivelyVisible;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.component : WidgetComponent;
import yguilib.widget.layout_components : Anchor, Insets, Size;
import yguilib.widget.system : WidgetSystemContext;
import yguilib.widget.visible : findTopmostWithComponent;

package(yguilib):

/// Widget construction styling options shared by button builders.
struct ButtonBaseConfig {
  string text = "Button";
  ColorF normalBg = ColorF(0.20f, 0.22f, 0.28f, 1.0f);
  ColorF borderColor = ColorF(0.35f, 0.38f, 0.48f, 1.0f);
  ColorF textColor = ColorF(0.95f, 0.95f, 0.95f, 1.0f);
  float cornerRadius = 6.0f;
  float borderWidth = 1.0f;
  float fontSize = 13.0f;
  Insets padding = Insets(6.0f, 14.0f, 6.0f, 14.0f);
  string actionEvent = null;
}

/**
 * Fluent builder fields and setters shared by button builders.
 *
 * Mix into a struct builder; the host struct defines its own `action()` and
 * `build()` and calls `makeButtonBase` to create the common widget base.
 */
mixin template ButtonBuilderCommon() {
  // Scoped imports: mixin bodies resolve names in the instantiating scope.
  import yguilib.controls.common : orDefault;
  import yguilib.controls.internal.button_support : ButtonBaseConfig,
    applyButtonBaseFace;
  import yguilib.controls.tooltip : Tooltip;
  import yguilib.render.render_types : ColorF, RectF;
  import yguilib.uisystem : UiSystem;
  import yguilib.widget : Widget;
  import yguilib.widget.builder : WidgetBuilder;
  import yguilib.widget.layout_components : Anchor, Insets, Size;

  ButtonBaseConfig config;
  Size customSize = null;
  Anchor customAnchor = null;
  string widgetName = null;
  bool hasTooltip = false;
  string tooltipHint = null;

  /// Sets the widget name (a default is used when empty).
  ref typeof(this) name(string buttonName) return {
    widgetName = buttonName;
    return this;
  }

  /// Sets the caption text.
  ref typeof(this) text(string caption) return {
    config.text = caption;
    return this;
  }

  /// Sets the normal background colour.
  ref typeof(this) bg(ColorF color) return {
    config.normalBg = color;
    return this;
  }

  /// Sets the border colour and width.
  ref typeof(this) border(ColorF color, float width) return {
    config.borderColor = color;
    config.borderWidth = width;
    return this;
  }

  /// Sets the corner radius.
  ref typeof(this) radius(float r) return {
    config.cornerRadius = r;
    return this;
  }

  /// Sets vertical and horizontal caption padding.
  ref typeof(this) padding(float vertical, float horizontal) return {
    config.padding = Insets.vh(vertical, horizontal);
    return this;
  }

  /// Sets the caption font size in points.
  ref typeof(this) fontSize(float pt) return {
    config.fontSize = pt;
    return this;
  }

  /// Sets a custom `Size` component (`sz` must not be null).
  ref typeof(this) size(Size sz) return {
    customSize = sz;
    return this;
  }

  /// Sets a fixed `w` x `h` size.
  ref typeof(this) fixedSize(float w, float h) return {
    customSize = Size.fixed(w, h);
    return this;
  }

  /// Sizes the button to its content.
  ref typeof(this) autoSize() return {
    customSize = Size.autoSize();
    return this;
  }

  /// Sets a custom `Anchor` component (`a` must not be null).
  ref typeof(this) anchor(Anchor a) return {
    customAnchor = a;
    return this;
  }

  /// Attaches a tooltip whose text is taken from the caption.
  ref typeof(this) captionTooltip() return {
    hasTooltip = true;
    tooltipHint = null;
    return this;
  }

  /// Attaches a tooltip showing `hintText`.
  ref typeof(this) tooltipText(string hintText) return {
    hasTooltip = true;
    tooltipHint = hintText;
    return this;
  }

  /**
   * Creates a `WidgetBuilder` with name, rect, size, anchor, padding, face
   * style, optional tooltip and input enabled. `parent` may be null. Callers
   * attach their own component(s) and call `build()` on the result.
   */
  WidgetBuilder makeButtonBase(
    UiSystem ui,
    Widget parent,
    RectF rect,
    string defaultName
  ) {
    const float initW = rect.width > 0.0f ? rect.width : 100.0f;
    const float initH = rect.height > 0.0f ? rect.height : 36.0f;
    const string btnName = orDefault(widgetName, defaultName);

    auto b = WidgetBuilder.make(ui)
      .parent(parent)
      .name(btnName)
      .rect(rect);

    if (customSize !is null) {
      b.sizeComponent(customSize);
    } else {
      b.fixedSize(initW, initH);
    }
    if (customAnchor !is null) {
      b.anchorComponent(customAnchor);
    }

    b.padding(config.padding);
    applyButtonBaseFace(b, config);
    if (hasTooltip) {
      b.component(Tooltip.withText(tooltipHint));
    }
    b.inputEnabled(true);
    return b;
  }
}

/// Applies background, border and caption label from `config` to `b`.
void applyButtonBaseFace(ref WidgetBuilder b, in ButtonBaseConfig config) {
  ButtonFace face;
  face.colors = WidgetColors(
    config.normalBg,
    config.borderColor,
    config.textColor
  );
  face.cornerRadius = config.cornerRadius;
  face.borderWidth = config.borderWidth;
  face.fontSize = config.fontSize;
  applyButtonFaceStyle(b, config.text, face);
}

/// Set of widgets with ongoing per-widget work (e.g. running animations).
struct ActiveWidgets {
  /// Adds `w` once; null is allowed and ignored.
  void track(Widget w) {
    if (w is null) {
      return;
    }
    items.addUnique(w);
  }

  /// Removes `w` if present; null is allowed and ignored.
  void remove(Widget w) {
    if (w is null) {
      return;
    }
    items.removeFirst(w);
  }

  /// Returns true when no widget is tracked.
  @property bool empty() const nothrow @safe {
    return items.empty;
  }

  /// Returns the number of tracked widgets.
  @property size_t length() const nothrow @safe {
    return items.length;
  }

  /// Returns the tracked widget at `idx`.
  Widget opIndex(size_t idx) {
    return items[idx];
  }

  /// Removes the tracked widget at `idx`.
  void removeAt(size_t idx) {
    items.removeAt(idx);
  }

  /// Drops widgets that are not effectively visible, calling `onRemoved`
  /// for each dropped widget (iterates backwards).
  void removeInvisible(scope void delegate(Widget) onRemoved) {
    assert(onRemoved !is null, "onRemoved must not be null");
    for (ptrdiff_t i = cast(ptrdiff_t) items.length - 1; i >= 0; --i) {
      Widget w = items[i];
      if (!isEffectivelyVisible(w)) {
        onRemoved(w);
        items.removeAt(cast(size_t) i);
      }
    }
  }

private:
  ReusableArray!Widget items;
}

/// Tracks the widget pressed by the primary mouse button until release.
struct PressTracker(C : WidgetComponent) {
  /// Currently pressed widget, or null.
  Widget pressed = null;

  /// Returns the topmost visible widget with component `C` at `p`, or null.
  static Widget hitTest(ref WidgetSystemContext ctx, PointF p) {
    return findTopmostWithComponent!C(ctx.visibleWidgets, p);
  }

  /// Starts tracking `w` as pressed.
  void begin(Widget w) {
    assert(w !is null, "w must not be null");
    pressed = w;
  }

  /// Returns the pressed widget (may be null) and stops tracking it.
  Widget end() {
    Widget w = pressed;
    pressed = null;
    return w;
  }

  /// Stops tracking if `w` is the pressed widget.
  void forget(Widget w) {
    if (pressed is w) {
      pressed = null;
    }
  }

  /// Stops tracking if the pressed widget is no longer effectively visible.
  void forgetInvisible() {
    if (pressed !is null && !isEffectivelyVisible(pressed)) {
      pressed = null;
    }
  }
}

/// Sends a view event `actionEvent` targeting `target` through `ctx.host`.
/// No-op when `ctx.host` is null or `actionEvent` is empty.
void emitButtonAction(
  ref WidgetSystemContext ctx,
  Widget target,
  string actionEvent
) {
  if (ctx.host is null || actionEvent.length == 0) {
    return;
  }
  auto ev = ViewAppEventBuilder(actionEvent)
    .widget(target)
    .build();
  ctx.host.sendAppEvent(ev);
}

// Unit tests for button builder mixin and shared tracking helpers
unittest {
  import yguilib.controls.testing : DummyWidgetSystemHost;
  import yguilib.events : AppEvent;
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.visible : VisibleWidget;

  static final class MarkerComponent : WidgetComponent {}

  static struct TestBuilder {
    mixin ButtonBuilderCommon;

    Widget build(UiSystem ui, Widget parent, RectF rect) {
      auto b = makeButtonBase(ui, parent, rect, "testButton");
      b.component(new MarkerComponent());
      return b.build();
    }
  }

  auto testUi = new UiSystemImpl(null);

  // Mixin setters + makeButtonBase widget tree
  TestBuilder tb;
  auto btn = tb
    .text("Caption")
    .bg(ColorF(0.1f, 0.2f, 0.3f, 1.0f))
    .border(ColorF(0.4f, 0.5f, 0.6f, 1.0f), 2.0f)
    .radius(3.0f)
    .fontSize(15.0f)
    .padding(2.0f, 4.0f)
    .fixedSize(90.0f, 30.0f)
    .tooltipText("Hint")
    .build(testUi, null, RectF(5, 5, 90, 30));
  assert(btn !is null);
  assert(btn.name == "testButton");
  assert(btn.inputEnabled);
  assert(btn.components.background !is null);
  assert(btn.components.background.color == ColorF(0.1f, 0.2f, 0.3f, 1.0f));
  assert(btn.components.border !is null);
  assert(btn.components.border.color == ColorF(0.4f, 0.5f, 0.6f, 1.0f));
  assert(btn.components.textLabel !is null);
  assert(btn.components.textLabel.caption == "Caption");
  assert(btn.components.size !is null);
  assert(btn.components.size.padding == Insets.vh(2.0f, 4.0f));
  assert(btn.components.has!MarkerComponent());
  assert(btn.components.has!Tooltip());
  assert(btn.components.get!Tooltip().resolveText(btn) == "Hint");

  // Name override and default size fallback with caption tooltip
  TestBuilder tb2;
  auto named = tb2.name("custom").captionTooltip()
    .build(testUi, null, RectF.init);
  assert(named.name == "custom");
  assert(named.components.size !is null);
  assert(named.components.get!Tooltip().resolveText(named) == "Button");

  // ActiveWidgets track/remove/removeInvisible
  ActiveWidgets active;
  assert(active.empty);
  active.track(null);
  assert(active.empty);
  active.track(btn);
  active.track(btn);
  active.track(named);
  assert(active.length == 2);
  assert(active[0] is btn);
  active.remove(btn);
  assert(active.length == 1);
  assert(active[0] is named);
  active.track(btn);
  named.visible = false;
  Widget[] dropped;
  active.removeInvisible((Widget w) { dropped ~= w; });
  assert(dropped.length == 1 && dropped[0] is named);
  assert(active.length == 1 && active[0] is btn);
  active.removeAt(0);
  assert(active.empty);

  // PressTracker begin/end/forget/forgetInvisible/hitTest
  WidgetSystemContext ctx;
  ctx.visibleWidgets = [
    VisibleWidget(btn, RectF(5, 5, 90, 30), false, RectF.init),
  ];
  PressTracker!MarkerComponent press;
  assert(press.hitTest(ctx, PointF(10, 10)) is btn);
  assert(press.hitTest(ctx, PointF(0, 0)) is null);
  press.begin(btn);
  assert(press.pressed is btn);
  assert(press.end() is btn);
  assert(press.pressed is null);
  assert(press.end() is null);
  press.begin(btn);
  press.forget(named);
  assert(press.pressed is btn);
  press.forget(btn);
  assert(press.pressed is null);
  press.begin(named);
  press.forgetInvisible();
  assert(press.pressed is null);

  // emitButtonAction sends one view event; nothing for empty name/no host
  auto host = new DummyWidgetSystemHost();
  emitButtonAction(ctx, btn, "click");
  ctx.host = host;
  emitButtonAction(ctx, btn, "");
  emitButtonAction(ctx, btn, null);
  assert(host.sentEvents.length == 0);
  emitButtonAction(ctx, btn, "click");
  assert(host.sentEvents.length == 1);
  assert(host.sentEvents[0].kind == AppEvent.Kind.view);
  assert(host.sentEvents[0].view.eventName == "click");
  assert(host.sentEvents[0].view.widget is btn);
}
