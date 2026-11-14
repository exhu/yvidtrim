module yguilib.widget.builder;

import std.typecons : Nullable;
import yguilib.render : Renderer;
import yguilib.render.font : defaultFontPtSize;
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.widget : ViewComponent, Widget, WidgetUpdateScope;
import yguilib.widget.component : WidgetComponent;
import yguilib.widget.data_components : WidgetArrayComponent,
  WidgetArrayProvider;
import yguilib.widget.drawing_components : Background, Border, CustomDraw,
  TextLabel;
import yguilib.widget.input_components : DefaultButton, Focus, MouseEvent;
import yguilib.widget.layout_components : AlignItems, Anchor, Dimension,
  FlexContainer, FlexDirection, Insets, JustifyContent, Size, SizingMode;
import yguilib.widget.scroll_components : ScrollableArea;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget.widget_view : WidgetView;

/// Fluent builder for constructing and configuring widgets with orthogonal
/// per-field modifiers and explicit `.build()` finalization.
final class WidgetBuilder {
  /// Creates a new WidgetBuilder backed by `ui.makeWidget()`.
  static WidgetBuilder make(UiSystem ui) {
    return new WidgetBuilder(ui);
  }

  invariant {
    assert(fUi !is null);
    assert(fWidget !is null);
  }

  /// Attaches the widget to `parentWidget`. `parentWidget` is allowed to be
  /// null (leaves widget detached).
  WidgetBuilder parent(Widget parentWidget) {
    if (parentWidget !is null) {
      parentWidget.addChild(fWidget);
    }
    return this;
  }

  /// Sets the widget name.
  WidgetBuilder name(string widgetName) {
    fWidget.name = widgetName;
    return this;
  }

  /// Sets widget visibility.
  WidgetBuilder visible(bool v = true) {
    fWidget.visible = v;
    return this;
  }

  /// Enables or disables input handling on this widget.
  WidgetBuilder inputEnabled(bool enabled = true) {
    fWidget.inputEnabled = enabled;
    return this;
  }

  /// Sets whether this widget intercepts raw input events.
  WidgetBuilder handleInput(bool handle = true) {
    fWidget.handleInput = handle;
    return this;
  }

  /// Enables or disables clipping of this widget's own drawn content.
  WidgetBuilder clipContents(bool clip = true) {
    fWidget.clipContents = clip;
    return this;
  }

  /// Enables or disables clipping of child widgets to content bounds.
  WidgetBuilder clipChildren(bool clip = true) {
    fWidget.clipChildren = clip;
    return this;
  }

  /// Sets the widget's local x/y position.
  WidgetBuilder pos(float x, float y) {
    fWidget.rect.x = x;
    fWidget.rect.y = y;
    return this;
  }

  /// Sets the widget's geometry width and height without adding a Size
  /// component.
  WidgetBuilder size(float w, float h) {
    fWidget.rect.width = w;
    fWidget.rect.height = h;
    return this;
  }

  /// Sets the widget's full local bounds rectangle.
  WidgetBuilder bounds(float x, float y, float w, float h) {
    fWidget.rect = RectF(x, y, w, h);
    return this;
  }

  /// Sets the widget's initial rectangle from a RectF.
  WidgetBuilder rect(RectF r) {
    fWidget.rect = r;
    return this;
  }

  /// Attaches a pre-configured Size component.
  WidgetBuilder sizeComponent(Size sz) {
    assert(sz !is null, "Size component must not be null");
    fWidget.components.size = sz;
    return this;
  }

  /// Configures both width and height in fixed sizing mode and updates rect.
  WidgetBuilder fixedSize(float w, float h) {
    Size sz = ensureSize();
    sz.width = Dimension(w, SizingMode.fixed);
    sz.height = Dimension(h, SizingMode.fixed);
    fWidget.rect.width = w;
    fWidget.rect.height = h;
    return this;
  }

  /// Configures width in fixed sizing mode and updates rect.width.
  WidgetBuilder fixedWidth(float w) {
    ensureSize().width = Dimension(w, SizingMode.fixed);
    fWidget.rect.width = w;
    return this;
  }

  /// Configures height in fixed sizing mode and updates rect.height.
  WidgetBuilder fixedHeight(float h) {
    ensureSize().height = Dimension(h, SizingMode.fixed);
    fWidget.rect.height = h;
    return this;
  }

  /// Configures both width and height in auto sizing mode.
  WidgetBuilder autoSize() {
    Size sz = ensureSize();
    sz.width = Dimension(0, SizingMode.auto_);
    sz.height = Dimension(0, SizingMode.auto_);
    return this;
  }

  /// Configures width in auto sizing mode.
  WidgetBuilder autoWidth() {
    ensureSize().width = Dimension(0, SizingMode.auto_);
    return this;
  }

  /// Configures height in auto sizing mode.
  WidgetBuilder autoHeight() {
    ensureSize().height = Dimension(0, SizingMode.auto_);
    return this;
  }

  /// Configures width in fraction sizing mode with flex-grow weight `wFr`.
  WidgetBuilder fractionWidth(float wFr) {
    ensureSize().width = Dimension(wFr, SizingMode.fraction);
    return this;
  }

  /// Configures height in fraction sizing mode with flex-grow weight `hFr`.
  WidgetBuilder fractionHeight(float hFr) {
    ensureSize().height = Dimension(hFr, SizingMode.fraction);
    return this;
  }

  /// Sets the minimum width constraint.
  WidgetBuilder minWidth(float minW) {
    ensureSize().minWidth = minW;
    return this;
  }

  /// Sets the minimum height constraint.
  WidgetBuilder minHeight(float minH) {
    ensureSize().minHeight = minH;
    return this;
  }

  /// Sets the maximum width constraint.
  WidgetBuilder maxWidth(float maxW) {
    ensureSize().maxWidth = maxW;
    return this;
  }

  /// Sets the maximum height constraint.
  WidgetBuilder maxHeight(float maxH) {
    ensureSize().maxHeight = maxH;
    return this;
  }

  /// Sets padding from an Insets struct.
  WidgetBuilder padding(Insets insets) {
    ensureSize().padding = insets;
    return this;
  }

  /// Sets uniform padding on all four sides.
  WidgetBuilder paddingAll(float all) {
    ensureSize().padding = Insets.all(all);
    return this;
  }

  /// Sets vertical and horizontal padding.
  WidgetBuilder paddingVh(float vertical, float horizontal) {
    ensureSize().padding = Insets.vh(vertical, horizontal);
    return this;
  }

  /// Sets left and right padding.
  WidgetBuilder paddingHorizontal(float h) {
    Size sz = ensureSize();
    sz.padding.left = h;
    sz.padding.right = h;
    return this;
  }

  /// Sets top and bottom padding.
  WidgetBuilder paddingVertical(float v) {
    Size sz = ensureSize();
    sz.padding.top = v;
    sz.padding.bottom = v;
    return this;
  }

  /// Sets top padding.
  WidgetBuilder paddingTop(float v) {
    ensureSize().padding.top = v;
    return this;
  }

  /// Sets right padding.
  WidgetBuilder paddingRight(float v) {
    ensureSize().padding.right = v;
    return this;
  }

  /// Sets bottom padding.
  WidgetBuilder paddingBottom(float v) {
    ensureSize().padding.bottom = v;
    return this;
  }

  /// Sets left padding.
  WidgetBuilder paddingLeft(float v) {
    ensureSize().padding.left = v;
    return this;
  }

  /// Sets margin from an Insets struct.
  WidgetBuilder margin(Insets insets) {
    ensureSize().margin = insets;
    return this;
  }

  /// Sets uniform margin on all four sides.
  WidgetBuilder marginAll(float all) {
    ensureSize().margin = Insets.all(all);
    return this;
  }

  /// Sets vertical and horizontal margin.
  WidgetBuilder marginVh(float vertical, float horizontal) {
    ensureSize().margin = Insets.vh(vertical, horizontal);
    return this;
  }

  /// Sets left and right margin.
  WidgetBuilder marginHorizontal(float h) {
    Size sz = ensureSize();
    sz.margin.left = h;
    sz.margin.right = h;
    return this;
  }

  /// Sets top and bottom margin.
  WidgetBuilder marginVertical(float v) {
    Size sz = ensureSize();
    sz.margin.top = v;
    sz.margin.bottom = v;
    return this;
  }

  /// Sets top margin.
  WidgetBuilder marginTop(float v) {
    ensureSize().margin.top = v;
    return this;
  }

  /// Sets right margin.
  WidgetBuilder marginRight(float v) {
    ensureSize().margin.right = v;
    return this;
  }

  /// Sets bottom margin.
  WidgetBuilder marginBottom(float v) {
    ensureSize().margin.bottom = v;
    return this;
  }

  /// Sets left margin.
  WidgetBuilder marginLeft(float v) {
    ensureSize().margin.left = v;
    return this;
  }

  /// Configures a horizontal row FlexContainer.
  WidgetBuilder flexRow() {
    ensureFlex().direction = FlexDirection.row;
    return this;
  }

  /// Configures a vertical column FlexContainer.
  WidgetBuilder flexColumn() {
    ensureFlex().direction = FlexDirection.column;
    return this;
  }

  /// Sets FlexContainer main-axis direction.
  WidgetBuilder flexDirection(FlexDirection dir) {
    ensureFlex().direction = dir;
    return this;
  }

  /// Sets spacing gap between flex children.
  WidgetBuilder gap(float g) {
    ensureFlex().gap = g;
    return this;
  }

  /// Sets FlexContainer main-axis justification.
  WidgetBuilder justify(JustifyContent j) {
    ensureFlex().justify = j;
    return this;
  }

  /// Sets FlexContainer cross-axis item alignment.
  WidgetBuilder alignItems(AlignItems a) {
    ensureFlex().alignItems = a;
    return this;
  }

  /// Attaches a pre-configured FlexContainer component.
  WidgetBuilder flexComponent(FlexContainer fc) {
    assert(fc !is null, "FlexContainer must not be null");
    fWidget.components.flexContainer = fc;
    return this;
  }

  /// Sets the left anchor offset.
  WidgetBuilder anchorLeft(float left) {
    import std.typecons : nullable;
    ensureAnchor().left = nullable(left);
    return this;
  }

  /// Sets the top anchor offset.
  WidgetBuilder anchorTop(float top) {
    import std.typecons : nullable;
    ensureAnchor().top = nullable(top);
    return this;
  }

  /// Sets the right anchor offset.
  WidgetBuilder anchorRight(float right) {
    import std.typecons : nullable;
    ensureAnchor().right = nullable(right);
    return this;
  }

  /// Sets the bottom anchor offset.
  WidgetBuilder anchorBottom(float bottom) {
    import std.typecons : nullable;
    ensureAnchor().bottom = nullable(bottom);
    return this;
  }

  /// Attaches a pre-configured Anchor component.
  WidgetBuilder anchorComponent(Anchor a) {
    assert(a !is null, "Anchor must not be null");
    fWidget.components.anchor = a;
    return this;
  }

  /// Sets the background color (creating a rect Background if absent).
  WidgetBuilder bg(ColorF color) {
    ensureBg().color = color;
    return this;
  }

  /// Sets a rounded background color (creating a round Background if absent).
  WidgetBuilder roundBg(ColorF color) {
    Background b = ensureBg(Background.Style.round, 6.0f);
    b.color = color;
    b.style = Background.Style.round;
    return this;
  }

  /// Sets the background style.
  WidgetBuilder bgStyle(Background.Style style) {
    ensureBg().style = style;
    return this;
  }

  /// Sets the background corner radius.
  WidgetBuilder bgRadius(float cornerRadius) {
    ensureBg().cornerRadius = cornerRadius;
    return this;
  }

  /// Attaches a pre-configured Background component.
  WidgetBuilder bgComponent(Background b) {
    assert(b !is null, "Background must not be null");
    fWidget.components.background = b;
    return this;
  }

  /// Sets the border color (creating a rect Border if absent).
  WidgetBuilder border(ColorF color) {
    ensureBorder().color = color;
    return this;
  }

  /// Sets a rounded border color (creating a round Border if absent).
  WidgetBuilder roundBorder(ColorF color) {
    Border b = ensureBorder(Border.Style.round, 6.0f);
    b.color = color;
    b.style = Border.Style.round;
    return this;
  }

  /// Sets the border stroke width in logical points.
  WidgetBuilder borderWidth(float width) {
    ensureBorder().width = width;
    return this;
  }

  /// Sets the border style.
  WidgetBuilder borderStyle(Border.Style style) {
    ensureBorder().style = style;
    return this;
  }

  /// Sets the border corner radius.
  WidgetBuilder borderRadius(float cornerRadius) {
    ensureBorder().cornerRadius = cornerRadius;
    return this;
  }

  /// Sets the dash length for dashed borders.
  WidgetBuilder borderDashLen(float dashLen) {
    ensureBorder().dashLen = dashLen;
    return this;
  }

  /// Sets the gap length between dashes for dashed borders.
  WidgetBuilder borderDashGap(float gap) {
    ensureBorder().gap = gap;
    return this;
  }

  /// Attaches a pre-configured Border component.
  WidgetBuilder borderComponent(Border b) {
    assert(b !is null, "Border must not be null");
    fWidget.components.border = b;
    return this;
  }

  /// Sets the TextLabel caption (`caption` is allowed to be null).
  WidgetBuilder text(string caption) {
    ensureText().caption = caption;
    return this;
  }

  /// Sets the TextLabel text color.
  WidgetBuilder textColor(ColorF color) {
    ensureText().color = color;
    return this;
  }

  /// Sets the TextLabel font size in points.
  WidgetBuilder fontSize(float pt) {
    ensureText().fontSize = pt;
    return this;
  }

  /// Sets the TextLabel font name (`fontName` is allowed to be null/empty).
  WidgetBuilder font(string fontName) {
    ensureText().font = fontName;
    return this;
  }

  /// Sets the TextLabel horizontal alignment.
  WidgetBuilder textAlign(TextLabel.Alignment align_) {
    ensureText().alignment = align_;
    return this;
  }

  /// Enables or disables multiline wrapping on TextLabel.
  WidgetBuilder multiline(bool multi = true) {
    ensureText().multiline = multi;
    return this;
  }

  /// Enables or disables overflow ellipsis truncation on TextLabel.
  WidgetBuilder ellipsis(bool enabled = true) {
    ensureText().overflowEllipsis = enabled;
    return this;
  }

  /// Attaches a pre-configured TextLabel component.
  WidgetBuilder textComponent(TextLabel tl) {
    assert(tl !is null, "TextLabel must not be null");
    fWidget.components.textLabel = tl;
    return this;
  }

  /// Attaches a CustomDraw delegate (`drawFunc` is allowed to be null).
  WidgetBuilder onDraw(void delegate(in Renderer, in Widget) drawFunc) {
    if (fWidget.components.customDraw is null) {
      fWidget.components.customDraw = new CustomDraw();
    }
    fWidget.components.customDraw.drawFunc = drawFunc;
    return this;
  }

  /// Sets the mouse-down view event name and enables input on the widget.
  WidgetBuilder onMouseDown(string eventName) {
    fWidget.inputEnabled = true;
    ensureMouseEvent().mouseDown = eventName;
    return this;
  }

  /// Sets the mouse-up view event name and enables input on the widget.
  WidgetBuilder onMouseUp(string eventName) {
    fWidget.inputEnabled = true;
    ensureMouseEvent().mouseUp = eventName;
    return this;
  }

  /// Sets the mouse-enter view event name.
  WidgetBuilder onMouseEnter(string eventName) {
    ensureMouseEvent().mouseEnter = eventName;
    return this;
  }

  /// Sets the mouse-leave view event name.
  WidgetBuilder onMouseLeave(string eventName) {
    ensureMouseEvent().mouseLeave = eventName;
    return this;
  }

  /// Sets the mouse-move view event name.
  WidgetBuilder onMouseMove(string eventName) {
    ensureMouseEvent().mouseMove = eventName;
    return this;
  }

  /// Attaches a ViewComponent marking this widget as a view boundary.
  WidgetBuilder view() {
    ensureView();
    return this;
  }

  /// Sets event rename mappings on the widget's ViewComponent (`events` is
  /// allowed to be null).
  WidgetBuilder viewEvents(string[string] events) {
    ensureView().renameEvents = events;
    return this;
  }

  /// Sets the WidgetView name on the widget's ViewComponent
  /// (`widgetViewName` is allowed to be null/empty).
  WidgetBuilder viewName(string widgetViewName) {
    ensureView().widgetViewName = widgetViewName;
    return this;
  }

  /// Attaches a ScrollableArea component and enables child clipping.
  WidgetBuilder scrollableArea() {
    fWidget.clipChildren = true;
    ensureScrollableArea();
    return this;
  }

  /// Sets the ScrollableArea initial offset and enables child clipping.
  WidgetBuilder scrollOffset(float x, float y) {
    fWidget.clipChildren = true;
    ensureScrollableArea().offset = PointF(x, y);
    return this;
  }

  /// Sets whether ScrollSystem clamps the scroll offset and enables child
  /// clipping.
  WidgetBuilder scrollClamp(bool clamp) {
    fWidget.clipChildren = true;
    ensureScrollableArea().clampOffset = clamp;
    return this;
  }

  /// Sets the ScrollableArea scroll-changed event name (`eventName` is allowed
  /// to be null) and enables child clipping.
  WidgetBuilder onScrollChanged(string eventName) {
    fWidget.clipChildren = true;
    ensureScrollableArea().scrollChangedEvent = eventName;
    return this;
  }

  /// Attaches a pre-configured ScrollableArea component and enables child
  /// clipping.
  WidgetBuilder scrollableAreaComponent(ScrollableArea sa) {
    assert(sa !is null, "ScrollableArea must not be null");
    fWidget.clipChildren = true;
    fWidget.components.scrollableArea = sa;
    return this;
  }

  /// Sets the WidgetArrayComponent provider (`provider` is allowed to be
  /// null).
  WidgetBuilder widgetArray(WidgetArrayProvider provider) {
    ensureWidgetArray().provider = provider;
    return this;
  }

  /// Sets the item count on WidgetArrayComponent.
  WidgetBuilder widgetArrayCount(size_t itemsCount) {
    ensureWidgetArray().itemsCount = itemsCount;
    return this;
  }

  /// Attaches a pre-configured WidgetArrayComponent.
  WidgetBuilder widgetArrayComponent(WidgetArrayComponent wa) {
    assert(wa !is null, "WidgetArrayComponent must not be null");
    fWidget.components.widgetArray = wa;
    return this;
  }

  /// Attaches a Focus component with initial focused state.
  WidgetBuilder focus(bool focused = false) {
    ensureFocus().focused = focused;
    return this;
  }

  /// Sets whether the Focus component skips this widget in tab traversal.
  WidgetBuilder focusSkip(bool skip = true) {
    ensureFocus().skip = skip;
    return this;
  }

  /// Marks this widget as a focus-cycling root.
  WidgetBuilder focusRoot(bool root = true) {
    ensureFocus().focusRoot = root;
    return this;
  }

  /// Marks this widget as the default button activated by Enter.
  WidgetBuilder defaultButton(bool isDefault = true) {
    if (isDefault) {
      if (fWidget.components.defaultButton is null) {
        fWidget.components.defaultButton = new DefaultButton();
      }
    } else {
      fWidget.components.defaultButton = null;
    }
    return this;
  }

  /// Attaches or replaces a custom WidgetComponent of type `C`.
  /// `comp` is allowed to be null (removes the component).
  WidgetBuilder component(C : WidgetComponent)(C comp) {
    fWidget.components.set!C(comp);
    return this;
  }

  /// Configures and attaches a child widget using this builder's UiSystem.
  WidgetBuilder child(scope void delegate(WidgetBuilder) config) {
    auto cb = new WidgetBuilder(fUi).parent(fWidget);
    if (config !is null) {
      config(cb);
    }
    cb.build();
    return this;
  }

  /// Attaches one or more already-built child widgets to this widget.
  WidgetBuilder children(Widget[] childWidgets...) {
    foreach (cw; childWidgets) {
      assert(cw !is null, "Child widget must not be null");
      fWidget.addChild(cw);
    }
    return this;
  }

  /// Finalizes construction, registers any named WidgetView with `UiSystem`,
  /// updates `parentView` scope, and returns the constructed `Widget`.
  Widget build() {
    if (ViewComponent v = fWidget.components.view) {
      if (v.widgetViewName.length > 0 && fUi.widgetViews !is null) {
        if (WidgetView wv = fUi.widgetViews.getByName(v.widgetViewName)) {
          wv.registerViewWidget(fWidget);
        }
      }
    }
    fWidget.update(WidgetUpdateScope.parentView);
    return fWidget;
  }

package(yguilib):
  @disable this();

  this(UiSystem ui) {
    assert(ui !is null, "UiSystem must not be null");
    fUi = ui;
    fWidget = ui.makeWidget();
  }

private:
  Size ensureSize() {
    if (fWidget.components.size is null) {
      fWidget.components.size = new Size();
    }
    return fWidget.components.size;
  }

  FlexContainer ensureFlex() {
    if (fWidget.components.flexContainer is null) {
      fWidget.components.flexContainer = new FlexContainer();
    }
    return fWidget.components.flexContainer;
  }

  Anchor ensureAnchor() {
    if (fWidget.components.anchor is null) {
      fWidget.components.anchor = new Anchor();
    }
    return fWidget.components.anchor;
  }

  Background ensureBg(
    Background.Style defaultStyle = Background.Style.rect,
    float defaultRadius = 0.0f
  ) {
    if (fWidget.components.background is null) {
      fWidget.components.background = new Background(
        ColorF(0, 0, 0, 0),
        defaultStyle,
        defaultRadius
      );
    }
    return fWidget.components.background;
  }

  Border ensureBorder(
    Border.Style defaultStyle = Border.Style.rect,
    float defaultRadius = 0.0f
  ) {
    if (fWidget.components.border is null) {
      auto b = new Border(ColorF(1, 1, 1, 1), 1.0f, defaultStyle);
      b.cornerRadius = defaultRadius;
      fWidget.components.border = b;
    }
    return fWidget.components.border;
  }

  TextLabel ensureText() {
    if (fWidget.components.textLabel is null) {
      fWidget.components.textLabel = new TextLabel("", ColorF(1, 1, 1, 1));
    }
    return fWidget.components.textLabel;
  }

  MouseEvent ensureMouseEvent() {
    if (fWidget.components.mouseEvent is null) {
      fWidget.components.mouseEvent = new MouseEvent();
    }
    return fWidget.components.mouseEvent;
  }

  ViewComponent ensureView() {
    if (fWidget.components.view is null) {
      fWidget.components.view = new ViewComponent();
    }
    return fWidget.components.view;
  }

  ScrollableArea ensureScrollableArea() {
    if (fWidget.components.scrollableArea is null) {
      fWidget.components.scrollableArea = new ScrollableArea();
    }
    return fWidget.components.scrollableArea;
  }

  WidgetArrayComponent ensureWidgetArray() {
    if (fWidget.components.widgetArray is null) {
      fWidget.components.widgetArray = new WidgetArrayComponent();
    }
    return fWidget.components.widgetArray;
  }

  Focus ensureFocus() {
    if (fWidget.components.focus is null) {
      fWidget.components.focus = new Focus();
    }
    return fWidget.components.focus;
  }

  UiSystem fUi;
  Widget fWidget;
}

/// Deprecated fluent builder for constructing and configuring widgets.
/// Use `WidgetBuilder` instead.
deprecated("Use WidgetBuilder instead")
struct LegacyWidgetBuilder {
  @disable this();

  /// Default method to create LegacyWidgetBuilder
  static LegacyWidgetBuilder make(UiSystem ui) {
    return LegacyWidgetBuilder(ui.nextWidgetId());
  }

  /// Attaches the widget to `parentWidget` if non-null.
  ref LegacyWidgetBuilder parent(Widget parentWidget) return {
    if (parentWidget !is null) {
      parentWidget.addChild(widget);
    }
    return this;
  }

  /// Sets the initial rectangle of the widget.
  ref LegacyWidgetBuilder rect(RectF r) return {
    widget.rect = r;
    return this;
  }

  ref LegacyWidgetBuilder name(string widgetName) return {
    widget.name = widgetName;
    return this;
  }

  ref LegacyWidgetBuilder padding(Insets insets) return {
    if (widget.components.size is null) {
      widget.components.size = new Size();
    }
    widget.components.size.padding = insets;
    return this;
  }

  ref LegacyWidgetBuilder padding(
    float top,
    float right,
    float bottom,
    float left
  ) return {
    return padding(Insets(top, right, bottom, left));
  }

  ref LegacyWidgetBuilder padding(float vertical, float horizontal) return {
    return padding(Insets.vh(vertical, horizontal));
  }

  ref LegacyWidgetBuilder padding(float all) return {
    return padding(Insets.all(all));
  }

  ref LegacyWidgetBuilder margin(Insets insets) return {
    if (widget.components.size is null) {
      widget.components.size = new Size();
    }
    widget.components.size.margin = insets;
    return this;
  }

  ref LegacyWidgetBuilder margin(
    float top,
    float right,
    float bottom,
    float left
  ) return {
    return margin(Insets(top, right, bottom, left));
  }

  ref LegacyWidgetBuilder margin(float vertical, float horizontal) return {
    return margin(Insets.vh(vertical, horizontal));
  }

  ref LegacyWidgetBuilder margin(float all) return {
    return margin(Insets.all(all));
  }

  ref LegacyWidgetBuilder size(Size sz) return {
    widget.components.size = sz;
    return this;
  }

  ref LegacyWidgetBuilder fixedSize(float w, float h) return {
    if (widget.components.size is null) {
      widget.components.size = Size.fixed(w, h);
    } else {
      widget.components.size.width = Dimension(w, SizingMode.fixed);
      widget.components.size.height = Dimension(h, SizingMode.fixed);
    }
    return this;
  }

  ref LegacyWidgetBuilder autoSize() return {
    if (widget.components.size is null) {
      widget.components.size = Size.autoSize();
    } else {
      widget.components.size.width = Dimension(0, SizingMode.auto_);
      widget.components.size.height = Dimension(0, SizingMode.auto_);
    }
    return this;
  }

  ref LegacyWidgetBuilder fractionSize(float wFr, float hFr = 0.0f) return {
    if (widget.components.size is null) {
      widget.components.size = Size.fraction(wFr, hFr);
    } else {
      widget.components.size.width = Dimension(wFr, SizingMode.fraction);
      widget.components.size.height = Dimension(
        hFr,
        hFr > 0.0f ? SizingMode.fraction : SizingMode.auto_
      );
    }
    return this;
  }

  ref LegacyWidgetBuilder minSize(float minW, float minH = 0.0f) return {
    if (widget.components.size is null) {
      widget.components.size = new Size();
    }
    widget.components.size.minWidth = minW;
    widget.components.size.minHeight = minH;
    return this;
  }

  ref LegacyWidgetBuilder maxSize(
    float maxW,
    float maxH = float.infinity
  ) return {
    if (widget.components.size is null) {
      widget.components.size = new Size();
    }
    widget.components.size.maxWidth = maxW;
    widget.components.size.maxHeight = maxH;
    return this;
  }

  ref LegacyWidgetBuilder background(
    ColorF color,
    Background.Style style = Background.Style.rect,
    float cornerRadius = 0.0f
  ) return {
    widget.components.background = new Background(color, style, cornerRadius);
    return this;
  }

  ref LegacyWidgetBuilder background(Background bg) return {
    widget.components.background = bg;
    return this;
  }

  ref LegacyWidgetBuilder roundBackground(
    ColorF color,
    float cornerRadius = 6.0f
  ) return {
    widget.components.background = Background.round(color, cornerRadius);
    return this;
  }

  ref LegacyWidgetBuilder border(
    ColorF color,
    float width = 1.0f,
    Border.Style style = Border.Style.rect,
    float cornerRadius = 0.0f
  ) return {
    auto b = new Border(color, width, style);
    if (cornerRadius > 0.0f) {
      b.cornerRadius = cornerRadius;
    }
    widget.components.border = b;
    return this;
  }

  ref LegacyWidgetBuilder border(Border b) return {
    widget.components.border = b;
    return this;
  }

  ref LegacyWidgetBuilder text(
    string caption,
    ColorF color = ColorF(1, 1, 1, 1),
    float fontSize = defaultFontPtSize,
    TextLabel.Alignment align_ = TextLabel.Alignment.left
  ) return {
    widget.components.textLabel = new TextLabel(caption, color)
      .withFontSize(fontSize)
      .withAlignment(align_);
    return this;
  }

  ref LegacyWidgetBuilder text(TextLabel tl) return {
    widget.components.textLabel = tl;
    return this;
  }

  ref LegacyWidgetBuilder flex(
    FlexDirection dir = FlexDirection.row,
    float gap = 0.0f,
    JustifyContent justify = JustifyContent.start,
    AlignItems align_ = AlignItems.stretch
  ) return {
    widget.components.flexContainer = new FlexContainer()
      .withDirection(dir)
      .withGap(gap)
      .withJustify(justify)
      .withAlign(align_);
    return this;
  }

  ref LegacyWidgetBuilder flex(FlexContainer fc) return {
    widget.components.flexContainer = fc;
    return this;
  }

  ref LegacyWidgetBuilder flexRow(
    float gap = 0.0f,
    JustifyContent justify = JustifyContent.start,
    AlignItems align_ = AlignItems.stretch
  ) return {
    return flex(FlexDirection.row, gap, justify, align_);
  }

  ref LegacyWidgetBuilder flexColumn(
    float gap = 0.0f,
    JustifyContent justify = JustifyContent.start,
    AlignItems align_ = AlignItems.stretch
  ) return {
    return flex(FlexDirection.column, gap, justify, align_);
  }

  ref LegacyWidgetBuilder anchor(
    Nullable!float left = Nullable!float.init,
    Nullable!float top = Nullable!float.init,
    Nullable!float right = Nullable!float.init,
    Nullable!float bottom = Nullable!float.init
  ) return {
    auto a = new Anchor();
    a.left = left;
    a.top = top;
    a.right = right;
    a.bottom = bottom;
    widget.components.anchor = a;
    return this;
  }

  ref LegacyWidgetBuilder anchor(Anchor a) return {
    widget.components.anchor = a;
    return this;
  }

  ref LegacyWidgetBuilder onMouseDown(string eventName) return {
    widget.inputEnabled = true;
    if (widget.components.mouseEvent is null) {
      widget.components.mouseEvent = new MouseEvent();
    }
    widget.components.mouseEvent.mouseDown = eventName;
    return this;
  }

  ref LegacyWidgetBuilder onMouseUp(string eventName) return {
    widget.inputEnabled = true;
    if (widget.components.mouseEvent is null) {
      widget.components.mouseEvent = new MouseEvent();
    }
    widget.components.mouseEvent.mouseUp = eventName;
    return this;
  }

  ref LegacyWidgetBuilder onMouseEnter(string eventName) return {
    if (widget.components.mouseEvent is null) {
      widget.components.mouseEvent = new MouseEvent();
    }
    widget.components.mouseEvent.mouseEnter = eventName;
    return this;
  }

  ref LegacyWidgetBuilder onMouseLeave(string eventName) return {
    if (widget.components.mouseEvent is null) {
      widget.components.mouseEvent = new MouseEvent();
    }
    widget.components.mouseEvent.mouseLeave = eventName;
    return this;
  }

  ref LegacyWidgetBuilder onMouseMove(string eventName) return {
    if (widget.components.mouseEvent is null) {
      widget.components.mouseEvent = new MouseEvent();
    }
    widget.components.mouseEvent.mouseMove = eventName;
    return this;
  }

  ref LegacyWidgetBuilder clipContents(bool clip = true) return {
    widget.clipContents = clip;
    return this;
  }

  ref LegacyWidgetBuilder clipChildren(bool clip = true) return {
    widget.clipChildren = clip;
    return this;
  }

  /// Attaches a ViewComponent to mark a view root and optional event mappings.
  /// `registry`, `events`, and `widgetViewName` are allowed to be null.
  ref LegacyWidgetBuilder view(
    UiRegistry registry,
    string[string] events = null,
    string widgetViewName = null
  ) return {
    if (widget.components.view is null) {
      widget.components.view = new ViewComponent();
    }
    ViewComponent view = widget.components.view;
    view.renameEvents = events;
    if (widgetViewName.length > 0) {
      view.widgetViewName = widgetViewName;
    }
    if (registry !is null) {
      if (string name = view.widgetViewName) {
        if (WidgetView wv = registry.widgetViews.getByName(name)) {
          wv.registerViewWidget(widget);
        }
      }
    }
    return this;
  }

  /// Appends and configures a child widget within a scoped delegate.
  ref LegacyWidgetBuilder child(
    UiSystem ui,
    scope void delegate(ref LegacyWidgetBuilder) config
  ) return {
    auto b = LegacyWidgetBuilder.make(ui).parent(widget);
    if (config !is null) {
      config(b);
    }
    return this;
  }

  /// Attaches a custom user-defined WidgetComponent of type C to the widget.
  ref LegacyWidgetBuilder component(C : WidgetComponent)(C comp) return {
    widget.components.set!C(comp);
    return this;
  }

  /// Attaches a WidgetArrayComponent with the given provider and item count.
  /// `provider` is allowed to be null during incremental configuration.
  ref LegacyWidgetBuilder widgetArray(
    WidgetArrayProvider provider,
    size_t itemsCount = 0
  ) return {
    auto wa = new WidgetArrayComponent();
    wa.provider = provider;
    wa.itemsCount = itemsCount;
    widget.components.widgetArray = wa;
    return this;
  }

  /// Attaches a pre-configured WidgetArrayComponent to the widget.
  /// `wa` is allowed to be null to clear the component.
  ref LegacyWidgetBuilder widgetArray(WidgetArrayComponent wa) return {
    widget.components.widgetArray = wa;
    return this;
  }

  /// Attaches a ScrollableArea component to the widget and enables child
  /// clipping.
  ref LegacyWidgetBuilder scrollableArea(ScrollableArea sa) return {
    widget.clipChildren = true;
    widget.components.scrollableArea = sa;
    return this;
  }

  /// Attaches a ScrollableArea with given offset and optional event name.
  ref LegacyWidgetBuilder scrollableArea(
    PointF offset = PointF(0.0f, 0.0f),
    string scrollChangedEvent = null
  ) return {
    return scrollableArea(new ScrollableArea()
      .withOffset(offset)
      .withScrollChangedEvent(scrollChangedEvent));
  }

  Widget build() {
    widget.update(WidgetUpdateScope.parentView);
    return widget;
  }

package(yguilib):
  /// Constructs a widget builder with an explicit unique ID.
  this(uint uId) {
    widget = new Widget(uId);
  }

  ref LegacyWidgetBuilder child(
    uint childId,
    scope void delegate(ref LegacyWidgetBuilder) config
  ) return {
    auto b = LegacyWidgetBuilder(childId).parent(widget);
    if (config !is null) {
      config(b);
    }
    return this;
  }


private:
  Widget widget;
}

/// Deprecated: Creates a flex row container widget.
deprecated("Use WidgetBuilder instead")
Widget flexRow(
  uint uId,
  Widget parent,
  RectF rect,
  float gap = 0.0f,
  JustifyContent justify = JustifyContent.start,
  AlignItems align_ = AlignItems.stretch
) {
  return LegacyWidgetBuilder(uId)
    .parent(parent)
    .rect(rect)
    .flex(FlexDirection.row, gap, justify, align_)
    .build();
}

/// Deprecated: Creates a flex row container and configures children inside a
/// delegate.
deprecated("Use WidgetBuilder instead")
Widget flexRow(
  uint uId,
  Widget parent,
  RectF rect,
  float gap,
  scope void delegate(Widget) populate
) {
  auto row = flexRow(uId, parent, rect, gap);
  if (populate !is null) {
    populate(row);
  }
  return row;
}

/// Deprecated: Creates a flex column container widget.
deprecated("Use WidgetBuilder instead")
Widget flexColumn(
  uint uId,
  Widget parent,
  RectF rect,
  float gap = 0.0f,
  JustifyContent justify = JustifyContent.start,
  AlignItems align_ = AlignItems.stretch
) {
  return LegacyWidgetBuilder(uId)
    .parent(parent)
    .rect(rect)
    .flex(FlexDirection.column, gap, justify, align_)
    .build();
}

/// Deprecated: Creates a flex column container and configures children inside a
/// delegate.
deprecated("Use WidgetBuilder instead")
Widget flexColumn(
  uint uId,
  Widget parent,
  RectF rect,
  float gap,
  scope void delegate(Widget) populate
) {
  auto col = flexColumn(uId, parent, rect, gap);
  if (populate !is null) {
    populate(col);
  }
  return col;
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.widget_view : WidgetViewBase;

  auto ui = new UiSystemImpl(null);

  // Basic hierarchy, flex, roundBg, border, child, and children tests
  auto root = WidgetBuilder.make(ui)
    .name("root")
    .bounds(10, 20, 800, 600)
    .flexRow()
    .gap(12.0f)
    .justify(JustifyContent.center)
    .alignItems(AlignItems.center)
    .roundBg(ColorF(0.1f, 0.12f, 0.15f, 1.0f))
    .bgRadius(8.0f)
    .border(ColorF(0.3f, 0.35f, 0.4f, 1.0f))
    .borderWidth(1.5f)
    .child((WidgetBuilder b) {
      b.name("child1")
        .fixedSize(100.0f, 40.0f)
        .paddingVh(4.0f, 8.0f)
        .margin(Insets.horizontal(10.0f).withTop(14.0f).withBottom(15.0f))
        .text("Child 1")
        .textColor(ColorF(1, 1, 1, 1))
        .fontSize(14.0f)
        .textAlign(TextLabel.Alignment.center)
        .multiline(true)
        .ellipsis(false)
        .onMouseDown("child1Click");
    })
    .children(
      WidgetBuilder.make(ui)
        .name("child2")
        .pos(5, 8)
        .size(120, 40)
        .autoSize()
        .minWidth(50.0f)
        .minHeight(20.0f)
        .maxWidth(200.0f)
        .maxHeight(100.0f)
        .text("Child 2")
        .build()
    )
    .build();

  assert(root !is null);
  assert(root.name == "root");
  assert(root.rect == RectF(10, 20, 800, 600));
  assert(root.children.length == 2);
  assert(root.components.flexContainer !is null);
  assert(root.components.flexContainer.direction == FlexDirection.row);
  assert(root.components.flexContainer.gap == 12.0f);
  assert(root.components.background.style == Background.Style.round);
  assert(root.components.background.cornerRadius == 8.0f);
  assert(root.components.border.width == 1.5f);

  auto c1 = root.children[0];
  assert(c1.name == "child1");
  assert(c1.rect.width == 100.0f && c1.rect.height == 40.0f);
  assert(c1.components.size.padding.top == 4.0f);
  assert(c1.components.size.padding.left == 8.0f);
  assert(c1.components.size.margin.left == 10.0f);
  assert(c1.components.size.margin.top == 14.0f);
  assert(c1.components.size.margin.bottom == 15.0f);
  assert(c1.components.textLabel.caption == "Child 1");
  assert(c1.components.textLabel.fontSize == 14.0f);
  assert(c1.components.textLabel.alignment == TextLabel.Alignment.center);
  assert(c1.components.textLabel.multiline);
  assert(!c1.components.textLabel.overflowEllipsis);
  assert(c1.inputEnabled);
  assert(c1.components.mouseEvent.mouseDown == "child1Click");

  auto c2 = root.children[1];
  assert(c2.name == "child2");
  assert(c2.rect == RectF(5, 8, 120, 40));
  assert(c2.components.size.minWidth == 50.0f);
  assert(c2.components.size.maxHeight == 100.0f);

  // Orthogonal padding/margin/anchor/border/fraction/visibility modifiers
  auto anchored = WidgetBuilder.make(ui)
    .parent(root)
    .name("anchored")
    .size(40, 24)
    .visible(false)
    .inputEnabled(false)
    .handleInput(true)
    .clipContents(false)
    .clipChildren(true)
    .bg(ColorF(0.2f, 0.3f, 0.4f, 1.0f))
    .bgStyle(Background.Style.none)
    .border(ColorF(0.9f, 0.8f, 0.7f, 1.0f))
    .borderStyle(Border.Style.dashed)
    .borderDashLen(6.0f)
    .borderDashGap(3.0f)
    .anchorRight(5.0f)
    .anchorBottom(2.0f)
    .paddingTop(1.0f)
    .paddingRight(2.0f)
    .paddingBottom(3.0f)
    .paddingLeft(4.0f)
    .fractionWidth(1.0f)
    .fixedHeight(30.0f)
    .build();

  assert(!anchored.visible);
  assert(!anchored.inputEnabled);
  assert(anchored.handleInput);
  assert(!anchored.clipContents);
  assert(anchored.clipChildren);
  assert(anchored.components.background.style == Background.Style.none);
  assert(anchored.components.border.style == Border.Style.dashed);
  assert(anchored.components.border.dashLen == 6.0f);
  assert(anchored.components.border.gap == 3.0f);
  assert(anchored.components.anchor.right.get == 5.0f);
  assert(anchored.components.anchor.bottom.get == 2.0f);
  assert(anchored.components.anchor.left.isNull);
  assert(anchored.components.size.padding == Insets(1, 2, 3, 4));
  assert(anchored.components.size.width.mode == SizingMode.fraction);
  assert(anchored.components.size.height.mode == SizingMode.fixed);
  assert(anchored.components.size.height.value == 30.0f);

  // Automatic WidgetView registration via viewName + UiSystem
  final class TestWidgetView : WidgetViewBase {
    override string getWidgetViewName() {
      return "TestViewName";
    }
  }
  auto testView = new TestWidgetView();
  ui.widgetViews.register(testView.getWidgetViewName(), testView);

  auto viewRoot = WidgetBuilder.make(ui)
    .name("viewRoot")
    .viewEvents(["btn": "press"])
    .viewName("TestViewName")
    .child((WidgetBuilder b) {
      b.name("viewChild");
    })
    .build();

  assert(viewRoot.components.view !is null);
  assert(viewRoot.components.view.renameEvents["btn"] == "press");
  assert(testView.isWidgetRegistered(viewRoot));
  assert(viewRoot.children[0].parentView is viewRoot);

  // ScrollableArea, WidgetArray, Focus, DefaultButton, and custom component
  final class DummyArrayProvider : WidgetArrayProvider {
    override void addWidget(Widget parent) {}
    override void updateWidgetAt(Widget w, size_t index) {}
  }
  final class ExtraDataComponent : WidgetComponent {
    int tag;
    this(int tag) {
      this.tag = tag;
    }
  }

  auto arrProvider = new DummyArrayProvider();
  auto extra = new ExtraDataComponent(42);
  auto featureWidget = WidgetBuilder.make(ui)
    .name("featureWidget")
    .scrollableArea()
    .scrollOffset(10.0f, 20.0f)
    .scrollClamp(false)
    .onScrollChanged("scrolled")
    .widgetArray(arrProvider)
    .widgetArrayCount(4)
    .focus(true)
    .focusSkip(false)
    .focusRoot(true)
    .defaultButton(true)
    .component(extra)
    .build();

  assert(featureWidget.clipChildren);
  assert(featureWidget.components.scrollableArea.offset == PointF(10, 20));
  assert(!featureWidget.components.scrollableArea.clampOffset);
  assert(featureWidget.components.scrollableArea.scrollChangedEvent ==
    "scrolled");
  assert(featureWidget.components.widgetArray.provider is arrProvider);
  assert(featureWidget.components.widgetArray.itemsCount == 4);
  assert(featureWidget.components.focus.focused);
  assert(!featureWidget.components.focus.skip);
  assert(featureWidget.components.focus.focusRoot);
  assert(featureWidget.components.defaultButton !is null);
  assert(featureWidget.components.get!ExtraDataComponent() is extra);
}

unittest {
  auto root = LegacyWidgetBuilder(1)
    .rect(RectF(0, 0, 800, 600))
    .flexRow(12.0f, JustifyContent.center, AlignItems.center)
    .roundBackground(ColorF(0.1f, 0.12f, 0.15f, 1.0f), 8.0f)
    .border(ColorF(0.3f, 0.35f, 0.4f, 1.0f), 1.0f)
    .child(2, (ref LegacyWidgetBuilder b) {
      b.rect(RectF(0, 0, 100, 40))
        .fixedSize(100.0f, 40.0f)
        .padding(4.0f, 8.0f)
        .margin(2.0f, 4.0f)
        .text("Child 1", ColorF(1, 1, 1, 1))
        .onMouseDown("child1Click");
    })
    .child(3, (ref LegacyWidgetBuilder b) {
      b.rect(RectF(0, 0, 120, 40))
        .autoSize()
        .minSize(50.0f, 20.0f)
        .maxSize(200.0f, 100.0f)
        .text("Child 2", ColorF(1, 1, 1, 1));
    })
    .build();

  assert(root !is null);
  assert(root.children.length == 2);
  assert(root.components.flexContainer !is null);
  assert(root.components.flexContainer.gap == 12.0f);
  assert(root.children[0].components.textLabel.caption == "Child 1");
  assert(root.children[0].components.mouseEvent.mouseDown == "child1Click");
  assert(root.children[0].components.size.margin.top == 2.0f);
  assert(root.children[1].components.textLabel.caption == "Child 2");
  assert(root.children[1].components.size.minWidth == 50.0f);

  // Component setter overloads test
  auto customBorder = Border.dashed(ColorF(1, 0, 0, 1), 2.0f, 4.0f, 2.0f);
  auto customText = new TextLabel("Custom").withMultiline(true);
  auto item = LegacyWidgetBuilder(4)
    .parent(root)
    .rect(RectF(0, 0, 50, 50))
    .border(customBorder)
    .text(customText)
    .padding(2.0f, 3.0f, 4.0f, 5.0f)
    .build();
  assert(item.components.border is customBorder);
  assert(item.components.textLabel is customText);
  assert(item.components.size.padding.left == 5.0f);

  // Factory container tests
  auto row = flexRow(5, root, RectF(0, 0, 200, 50), 6.0f, (Widget r) {
    auto w = new Widget(6);
    w.rect = RectF(0, 0, 50, 50);
    r.addChild(w);
  });
  assert(row.components.flexContainer.direction == FlexDirection.row);
  assert(row.components.flexContainer.gap == 6.0f);
  assert(row.children.length == 1);

  auto col = flexColumn(7, root, RectF(0, 0, 100, 200), 8.0f);
  assert(col.components.flexContainer.direction == FlexDirection.column);
  assert(col.components.flexContainer.gap == 8.0f);

  // View component test
  auto viewWidget = LegacyWidgetBuilder(8)
    .rect(RectF(0, 0, 100, 100))
    .view(null, ["btn": "press"])
    .build();
  assert(viewWidget.components.view !is null);
  assert(viewWidget.components.view.renameEvents["btn"] == "press");

  // Custom component builder test
  final class ExtraDataComponent : WidgetComponent {
    int tag;
    this(int tag) {
      this.tag = tag;
    }
  }
  auto extra = new ExtraDataComponent(42);
  auto customWidget = LegacyWidgetBuilder(9)
    .rect(RectF(0, 0, 50, 50))
    .component(extra)
    .build();
  assert(customWidget.components.has!ExtraDataComponent());
  assert(customWidget.components.get!ExtraDataComponent() is extra);
  assert(customWidget.components.get!ExtraDataComponent().tag == 42);

  // WidgetArrayComponent builder test
  final class DummyArrayProvider : WidgetArrayProvider {
    override void addWidget(Widget parent) {}
    override void updateWidgetAt(Widget w, size_t index) {}
  }
  auto arrProvider = new DummyArrayProvider();
  auto arrWidget = LegacyWidgetBuilder(10)
    .rect(RectF(0, 0, 100, 30))
    .widgetArray(arrProvider, 4)
    .build();
  assert(arrWidget.components.widgetArray !is null);
  assert(arrWidget.components.widgetArray.provider is arrProvider);
  assert(arrWidget.components.widgetArray.itemsCount == 4);
}
