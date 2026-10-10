module yguilib.widget.builder;

import std.typecons : Nullable;
import yguilib.render.font : defaultFontPtSize;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget.input_components : MouseEvent;
import yguilib.widget.layout_components : AlignItems, Anchor, Dimension,
  FlexContainer, FlexDirection, Insets, JustifyContent, Size, SizingMode;

/// Fluent builder for constructing and configuring widgets.
struct WidgetBuilder {
  /// Constructs a widget builder. Parent is allowed to be null.
  this(Widget parent, RectF rect) {
    widget = new Widget(parent, rect);
  }

  this(RectF rect) {
    widget = new Widget(null, rect);
  }

  ref WidgetBuilder padding(Insets insets) return {
    if (widget.components.size is null) {
      widget.components.size = new Size();
    }
    widget.components.size.padding = insets;
    return this;
  }

  ref WidgetBuilder padding(
    float top,
    float right,
    float bottom,
    float left
  ) return {
    return padding(Insets(top, right, bottom, left));
  }

  ref WidgetBuilder padding(float vertical, float horizontal) return {
    return padding(Insets(vertical, horizontal));
  }

  ref WidgetBuilder padding(float all) return {
    return padding(Insets(all));
  }

  ref WidgetBuilder margin(Insets insets) return {
    if (widget.components.size is null) {
      widget.components.size = new Size();
    }
    widget.components.size.margin = insets;
    return this;
  }

  ref WidgetBuilder margin(
    float top,
    float right,
    float bottom,
    float left
  ) return {
    return margin(Insets(top, right, bottom, left));
  }

  ref WidgetBuilder margin(float vertical, float horizontal) return {
    return margin(Insets(vertical, horizontal));
  }

  ref WidgetBuilder margin(float all) return {
    return margin(Insets(all));
  }

  ref WidgetBuilder size(Size sz) return {
    widget.components.size = sz;
    return this;
  }

  ref WidgetBuilder fixedSize(float w, float h) return {
    if (widget.components.size is null) {
      widget.components.size = Size.fixed(w, h);
    } else {
      widget.components.size.width = Dimension(w, SizingMode.fixed);
      widget.components.size.height = Dimension(h, SizingMode.fixed);
    }
    return this;
  }

  ref WidgetBuilder autoSize() return {
    if (widget.components.size is null) {
      widget.components.size = Size.autoSize();
    } else {
      widget.components.size.width = Dimension(0, SizingMode.auto_);
      widget.components.size.height = Dimension(0, SizingMode.auto_);
    }
    return this;
  }

  ref WidgetBuilder fractionSize(float wFr, float hFr = 0.0f) return {
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

  ref WidgetBuilder minSize(float minW, float minH = 0.0f) return {
    if (widget.components.size is null) {
      widget.components.size = new Size();
    }
    widget.components.size.minWidth = minW;
    widget.components.size.minHeight = minH;
    return this;
  }

  ref WidgetBuilder maxSize(float maxW, float maxH = float.infinity) return {
    if (widget.components.size is null) {
      widget.components.size = new Size();
    }
    widget.components.size.maxWidth = maxW;
    widget.components.size.maxHeight = maxH;
    return this;
  }

  ref WidgetBuilder background(
    ColorF color,
    Background.Style style = Background.Style.rect,
    float cornerRadius = 0.0f
  ) return {
    widget.components.background = new Background(color, style, cornerRadius);
    return this;
  }

  ref WidgetBuilder background(Background bg) return {
    widget.components.background = bg;
    return this;
  }

  ref WidgetBuilder roundBackground(
    ColorF color,
    float cornerRadius = 6.0f
  ) return {
    widget.components.background = Background.round(color, cornerRadius);
    return this;
  }

  ref WidgetBuilder border(
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

  ref WidgetBuilder border(Border b) return {
    widget.components.border = b;
    return this;
  }

  ref WidgetBuilder text(
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

  ref WidgetBuilder text(TextLabel tl) return {
    widget.components.textLabel = tl;
    return this;
  }

  ref WidgetBuilder flex(
    FlexDirection dir = FlexDirection.row,
    float gap = 0.0f,
    JustifyContent justify = JustifyContent.start,
    AlignItems align_ = AlignItems.stretch
  ) return {
    widget.components.flexContainer = new FlexContainer(dir, gap)
      .withJustify(justify)
      .withAlign(align_);
    return this;
  }

  ref WidgetBuilder flex(FlexContainer fc) return {
    widget.components.flexContainer = fc;
    return this;
  }

  ref WidgetBuilder flexRow(
    float gap = 0.0f,
    JustifyContent justify = JustifyContent.start,
    AlignItems align_ = AlignItems.stretch
  ) return {
    return flex(FlexDirection.row, gap, justify, align_);
  }

  ref WidgetBuilder flexColumn(
    float gap = 0.0f,
    JustifyContent justify = JustifyContent.start,
    AlignItems align_ = AlignItems.stretch
  ) return {
    return flex(FlexDirection.column, gap, justify, align_);
  }

  ref WidgetBuilder anchor(
    Nullable!float left = Nullable!float.init,
    Nullable!float top = Nullable!float.init,
    Nullable!float right = Nullable!float.init,
    Nullable!float bottom = Nullable!float.init
  ) return {
    widget.components.anchor = new Anchor(left, top, right, bottom);
    return this;
  }

  ref WidgetBuilder anchor(Anchor a) return {
    widget.components.anchor = a;
    return this;
  }

  ref WidgetBuilder onMouseDown(string eventName) return {
    widget.inputEnabled = true;
    if (widget.components.mouseEvent is null) {
      widget.components.mouseEvent = new MouseEvent();
    }
    widget.components.mouseEvent.mouseDown = eventName;
    return this;
  }

  ref WidgetBuilder clipContents(bool clip = true) return {
    widget.clipContents = clip;
    return this;
  }

  ref WidgetBuilder clipChildren(bool clip = true) return {
    widget.clipChildren = clip;
    return this;
  }

  /// Appends and configures a child widget within a scoped delegate.
  ref WidgetBuilder child(
    RectF rect,
    scope void delegate(ref WidgetBuilder) config
  ) return {
    auto b = WidgetBuilder(widget, rect);
    config(b);
    return this;
  }

  Widget build() {
    return widget;
  }

private:
  Widget widget;
}

/// Creates a flex row container widget.
Widget flexRow(
  Widget parent,
  RectF rect,
  float gap = 0.0f,
  JustifyContent justify = JustifyContent.start,
  AlignItems align_ = AlignItems.stretch
) {
  return WidgetBuilder(parent, rect)
    .flex(FlexDirection.row, gap, justify, align_)
    .build();
}

/// Creates a flex row container and configures children inside a delegate.
Widget flexRow(
  Widget parent,
  RectF rect,
  float gap,
  scope void delegate(Widget) populate
) {
  auto row = flexRow(parent, rect, gap);
  if (populate !is null) {
    populate(row);
  }
  return row;
}

/// Creates a flex column container widget.
Widget flexColumn(
  Widget parent,
  RectF rect,
  float gap = 0.0f,
  JustifyContent justify = JustifyContent.start,
  AlignItems align_ = AlignItems.stretch
) {
  return WidgetBuilder(parent, rect)
    .flex(FlexDirection.column, gap, justify, align_)
    .build();
}

/// Creates a flex column container and configures children inside a delegate.
Widget flexColumn(
  Widget parent,
  RectF rect,
  float gap,
  scope void delegate(Widget) populate
) {
  auto col = flexColumn(parent, rect, gap);
  if (populate !is null) {
    populate(col);
  }
  return col;
}

unittest {
  auto root = WidgetBuilder(RectF(0, 0, 800, 600))
    .flexRow(12.0f, JustifyContent.center, AlignItems.center)
    .roundBackground(ColorF(0.1f, 0.12f, 0.15f, 1.0f), 8.0f)
    .border(ColorF(0.3f, 0.35f, 0.4f, 1.0f), 1.0f)
    .child(RectF(0, 0, 100, 40), (ref WidgetBuilder b) {
      b.fixedSize(100.0f, 40.0f)
        .padding(4.0f, 8.0f)
        .margin(2.0f, 4.0f)
        .text("Child 1", ColorF(1, 1, 1, 1))
        .onMouseDown("child1Click");
    })
    .child(RectF(0, 0, 120, 40), (ref WidgetBuilder b) {
      b.autoSize()
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
  auto item = WidgetBuilder(root, RectF(0, 0, 50, 50))
    .border(customBorder)
    .text(customText)
    .padding(2.0f, 3.0f, 4.0f, 5.0f)
    .build();
  assert(item.components.border is customBorder);
  assert(item.components.textLabel is customText);
  assert(item.components.size.padding.left == 5.0f);

  // Factory container tests
  auto row = flexRow(root, RectF(0, 0, 200, 50), 6.0f, (Widget r) {
    new Widget(r, RectF(0, 0, 50, 50));
  });
  assert(row.components.flexContainer.direction == FlexDirection.row);
  assert(row.components.flexContainer.gap == 6.0f);
  assert(row.children.length == 1);

  auto col = flexColumn(root, RectF(0, 0, 100, 200), 8.0f);
  assert(col.components.flexContainer.direction == FlexDirection.column);
  assert(col.components.flexContainer.gap == 8.0f);
}
