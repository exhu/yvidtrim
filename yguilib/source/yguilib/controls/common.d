/**
 * common.d - Shared color, button face, registry, event, and composite tree
 * helpers for `yguilib.controls`.
 */
module yguilib.controls.common;

import std.typecons : Nullable;
import yguilib.events.builder : ViewAppEventBuilder;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Border, TextLabel;
import yguilib.widget.layout_components : Insets;

/// Triplet of background, border, and text colors for a styled control widget.
struct WidgetColors {
  ColorF bg;
  ColorF border;
  ColorF text;
}

/// Shared disabled state palette for composite control buttons.
enum defaultDisabledColors = WidgetColors(
  ColorF(0.11f, 0.12f, 0.15f, 1.0f),
  ColorF(0.19f, 0.21f, 0.25f, 1.0f),
  ColorF(0.39f, 0.42f, 0.48f, 1.0f)
);

/// Applies background, border, and text colors to `w`.
/// `w` is allowed to be null (no-op).
void applyColors(Widget w, in WidgetColors c) {
  if (w is null) {
    return;
  }
  w.setBackgroundColor(c.bg);
  w.setBorderColor(c.border);
  w.setTextColor(c.text);
}

/// Applies background and border colors to `w`.
/// `w` is allowed to be null (no-op).
void applyBgAndBorderColors(Widget w, ColorF bg, ColorF border) {
  if (w is null) {
    return;
  }
  w.setBackgroundColor(bg);
  w.setBorderColor(border);
}

/// Sets `w.inputEnabled` to `enabled` and applies `on` or `off` colors.
/// `w` is allowed to be null (no-op).
void applyEnabledState(
  Widget w,
  bool enabled,
  in WidgetColors on,
  in WidgetColors off
) {
  if (w is null) {
    return;
  }
  w.inputEnabled = enabled;
  applyColors(w, enabled ? on : off);
}

/// Styling and sizing parameters for a label-bearing button widget.
struct ButtonFace {
  WidgetColors colors;
  float width = 0.0f;
  float height = 0.0f;
  float cornerRadius = 4.0f;
  float borderWidth = 1.0f;
  float fontSize = 13.0f;
  Insets padding;
}

/// Applies background, optional border, and centered text styling from `face`
/// to `b`. `label` is allowed to be null/empty.
void applyButtonFaceStyle(
  ref WidgetBuilder b,
  string label,
  in ButtonFace face
) {
  assert(b !is null, "b must not be null");
  if (face.cornerRadius > 0.0f) {
    b.roundBg(face.colors.bg).bgRadius(face.cornerRadius);
  } else {
    b.bg(face.colors.bg);
  }

  if (face.borderWidth > 0.0f) {
    b.border(face.colors.border)
      .borderWidth(face.borderWidth)
      .borderStyle(
        face.cornerRadius > 0.0f ? Border.Style.round : Border.Style.rect
      )
      .borderRadius(face.cornerRadius);
  }

  b.text(label)
    .textColor(face.colors.text)
    .fontSize(face.fontSize)
    .textAlign(TextLabel.Alignment.center);
}

/// Creates a `WidgetBuilder` preconfigured as a fixed-size styled button.
/// `parent`, `name`, and `label` are allowed to be null.
WidgetBuilder styledButton(
  UiSystem ui,
  Widget parent,
  string name,
  string label,
  in ButtonFace face
) {
  assert(ui !is null, "ui must not be null");
  auto b = WidgetBuilder.make(ui)
    .parent(parent)
    .name(name)
    .rect(RectF(0, 0, face.width, face.height))
    .fixedSize(face.width, face.height);

  if (
    face.padding.top != 0.0f ||
    face.padding.right != 0.0f ||
    face.padding.bottom != 0.0f ||
    face.padding.left != 0.0f
  ) {
    b.padding(face.padding);
  }

  applyButtonFaceStyle(b, label, face);
  return b;
}

/// Returns `value` when non-empty, or `fallback` otherwise.
string orDefault(string value, string fallback) nothrow @safe @nogc {
  return (value.length > 0) ? value : fallback;
}

/// Returns the first positive (> 0) value among `a`, `b`, `c`, or 0.0f.
float firstPositive(float a, float b, float c) nothrow @safe @nogc {
  if (a > 0.0f) {
    return a;
  }
  if (b > 0.0f) {
    return b;
  }
  if (c > 0.0f) {
    return c;
  }
  return 0.0f;
}

/// Instantiates `V` and `C(ui)`, links them, and registers both in `ui`.
C registerWidgetViewPair(V, C)(UiSystem ui) {
  assert(ui !is null, "ui must not be null");
  auto view = new V();
  auto ctrl = new C(ui);
  ctrl.registerWidgetView(view);
  ui.widgetViews.register(view.getWidgetViewName(), view);
  ui.widgetViewControllers.register(ctrl.getControllerName(), ctrl);
  return ctrl;
}

/// Looks up a registered `WidgetView` by `name` and casts it to `V`.
/// `registry` is allowed to be null (returns null).
V findWidgetView(V)(UiRegistry registry, string name) {
  if (registry is null) {
    return null;
  }
  return cast(V) registry.widgetViews.getByName(name);
}

/// Sends a `ViewAppEventBuilder` event carrying `value` if `eventName` is
/// non-empty.
void emitViewValueEvent(
  UiSystem ui,
  string eventName,
  Widget viewWidget,
  ulong value
) {
  assert(ui !is null, "ui must not be null");
  assert(viewWidget !is null, "viewWidget must not be null");
  if (eventName.length == 0) {
    return;
  }
  auto ev = ViewAppEventBuilder(eventName)
    .widget(viewWidget)
    .viewWidget(viewWidget)
    .value(value)
    .build();
  ui.sendAppEvent(ev);
}

/// Discovered child widgets of a 3-child `[dec, middle, inc]` arrow composite.
struct ArrowCompositeParts {
  Widget dec;
  Widget middle;
  Widget inner;
  Widget inc;
}

/// Probes a 3-child `[dec, middle, inc]` composite where `middle` contains at
/// least one child (`inner`). `root` is allowed to be null (returns null
/// `Nullable`).
Nullable!ArrowCompositeParts findArrowComposite(Widget root) {
  if (root is null || root.children.length != 3) {
    return Nullable!ArrowCompositeParts.init;
  }
  Widget middle = root.children[1];
  if (middle.children.length == 0) {
    return Nullable!ArrowCompositeParts.init;
  }
  return Nullable!ArrowCompositeParts(
    ArrowCompositeParts(
      root.children[0],
      middle,
      middle.children[0],
      root.children[2]
    )
  );
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.drawing_components : Background;

  auto ui = new UiSystemImpl(null);
  const auto onColors = WidgetColors(
    ColorF(0.1f, 0.2f, 0.3f, 1.0f),
    ColorF(0.4f, 0.5f, 0.6f, 1.0f),
    ColorF(0.7f, 0.8f, 0.9f, 1.0f)
  );
  const auto offColors = defaultDisabledColors;

  // Null safety on color helpers
  applyColors(null, onColors);
  applyBgAndBorderColors(null, onColors.bg, onColors.border);
  applyEnabledState(null, true, onColors, offColors);

  auto face = ButtonFace(
    onColors, 120.0f, 32.0f, 5.0f, 1.5f, 14.0f, Insets(4, 6, 4, 6)
  );
  auto btn = styledButton(ui, null, "testBtn", "Click", face)
    .onMouseDown("btnDown")
    .build();
  assert(btn.name == "testBtn");
  assert(btn.rect == RectF(0, 0, 120.0f, 32.0f));
  assert(btn.components.size !is null);
  assert(btn.components.size.padding == Insets(4, 6, 4, 6));
  assert(btn.components.background.style == Background.Style.round);
  assert(btn.components.background.cornerRadius == 5.0f);
  assert(btn.components.background.color == onColors.bg);
  assert(btn.components.border !is null);
  assert(btn.components.border.style == Border.Style.round);
  assert(btn.components.border.width == 1.5f);
  assert(btn.components.border.color == onColors.border);
  assert(btn.components.textLabel.caption == "Click");
  assert(btn.components.textLabel.color == onColors.text);
  assert(btn.components.textLabel.fontSize == 14.0f);
  assert(btn.components.textLabel.alignment == TextLabel.Alignment.center);
  assert(btn.components.mouseEvent.mouseDown == "btnDown");

  // Rect background and no border when cornerRadius == 0 and borderWidth == 0
  auto flatFace = ButtonFace(
    offColors, 80.0f, 24.0f, 0.0f, 0.0f, 11.0f, Insets.init
  );
  auto flatBtn = styledButton(ui, null, "flatBtn", "Flat", flatFace).build();
  assert(flatBtn.components.size.padding == Insets.init);
  assert(flatBtn.components.background.style == Background.Style.rect);
  assert(flatBtn.components.border is null);

  applyBgAndBorderColors(btn, offColors.bg, offColors.border);
  assert(btn.components.background.color == offColors.bg);
  assert(btn.components.border.color == offColors.border);
  assert(btn.components.textLabel.color == onColors.text);

  applyEnabledState(btn, false, onColors, offColors);
  assert(!btn.inputEnabled);
  assert(btn.components.background.color == offColors.bg);
  assert(btn.components.border.color == offColors.border);
  assert(btn.components.textLabel.color == offColors.text);

  applyEnabledState(btn, true, onColors, offColors);
  assert(btn.inputEnabled);
  assert(btn.components.background.color == onColors.bg);
  assert(btn.components.border.color == onColors.border);
  assert(btn.components.textLabel.color == onColors.text);
}

unittest {
  assert(orDefault("custom", "fallback") == "custom");
  assert(orDefault("", "fallback") == "fallback");
  assert(orDefault(null, "fallback") == "fallback");

  assert(firstPositive(3.0f, 2.0f, 1.0f) == 3.0f);
  assert(firstPositive(0.0f, 2.0f, 1.0f) == 2.0f);
  assert(firstPositive(-1.0f, 0.0f, 5.0f) == 5.0f);
  assert(firstPositive(0.0f, -2.0f, 0.0f) == 0.0f);
}

unittest {
  import yguilib.controller : HandleResult;
  import yguilib.controls.testing : RecordingUiSystem;
  import yguilib.events : AppEvent;
  import yguilib.widget.widget_view : WidgetViewBase,
    WidgetViewControllerBase;

  static final class SampleView : WidgetViewBase {
    override bool update() {
      return false;
    }
  }

  static final class SampleController : WidgetViewControllerBase {
    this(UiSystem uiSystem) {
      assert(uiSystem !is null, "uiSystem must not be null");
      super(uiSystem);
    }

    override HandleResult handleEvent(AppEvent ev) {
      return super.handleEvent(ev);
    }
  }

  auto ui = new RecordingUiSystem();
  auto ctrl = registerWidgetViewPair!(SampleView, SampleController)(ui);
  assert(ctrl !is null);

  auto foundView = findWidgetView!SampleView(ui, "SampleView");
  assert(foundView !is null);
  assert(findWidgetView!SampleView(null, "SampleView") is null);
  assert(findWidgetView!SampleView(ui, "MissingView") is null);
  assert(ui.widgetViewControllers.getByName("SampleController") is ctrl);

  auto viewWidget = ui.makeWidget();
  emitViewValueEvent(ui, "", viewWidget, 99);
  assert(ui.sentEvents.length == 0);

  emitViewValueEvent(ui, "valueChanged", viewWidget, 42);
  assert(ui.sentEvents.length == 1);
  assert(ui.sentEvents[0].kind == AppEvent.Kind.view);
  assert(ui.sentEvents[0].view.eventName == "valueChanged");
  assert(ui.sentEvents[0].view.widget is viewWidget);
  assert(ui.sentEvents[0].view.viewWidget is viewWidget);
  assert(ui.sentEvents[0].view.value[0] == 42);
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
  assert(findArrowComposite(null).isNull);

  auto root = ui.makeWidget();
  auto c0 = ui.makeWidget();
  auto c1 = ui.makeWidget();
  root.addChild(c0);
  root.addChild(c1);
  assert(findArrowComposite(root).isNull);

  auto c2 = ui.makeWidget();
  root.addChild(c2);
  assert(findArrowComposite(root).isNull);

  auto c1Inner = ui.makeWidget();
  c1.addChild(c1Inner);
  auto found = findArrowComposite(root);
  assert(!found.isNull);
  auto parts = found.get();
  assert(
    parts.dec is c0 && parts.middle is c1 &&
    parts.inner is c1Inner && parts.inc is c2
  );
}
