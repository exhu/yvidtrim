module yguilib.widget.builder;

import yguilib.render : Renderer;
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
import yguilib.uisystem : UiSystem;
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
