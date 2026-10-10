module yguilib.widget.builder;

import std.typecons : Nullable;
import yguilib.render.font : defaultFontPtSize;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.drawing_components : Background, Border, TextLabel;
import yguilib.widget.layout_components : AlignItems, Dimension, FlexDirection,
  Insets, JustifyContent, Size, SizingMode;

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
    widget.withPadding(insets);
    return this;
  }

  ref WidgetBuilder padding(float vertical, float horizontal) return {
    widget.withPadding(vertical, horizontal);
    return this;
  }

  ref WidgetBuilder padding(float all) return {
    widget.withPadding(all);
    return this;
  }

  ref WidgetBuilder margin(Insets insets) return {
    widget.withMargin(insets);
    return this;
  }

  ref WidgetBuilder size(Size sz) return {
    widget.withSize(sz);
    return this;
  }

  ref WidgetBuilder fixedSize(float w, float h) return {
    widget.withFixedSize(w, h);
    return this;
  }

  ref WidgetBuilder autoSize() return {
    widget.withAutoSize();
    return this;
  }

  ref WidgetBuilder fractionSize(float wFr, float hFr = 0.0f) return {
    widget.withFractionSize(wFr, hFr);
    return this;
  }

  ref WidgetBuilder background(
    ColorF color,
    Background.Style style = Background.Style.rect,
    float cornerRadius = 0.0f
  ) return {
    widget.withBackground(color, style, cornerRadius);
    return this;
  }

  ref WidgetBuilder roundBackground(
    ColorF color,
    float cornerRadius = 6.0f
  ) return {
    widget.withRoundBackground(color, cornerRadius);
    return this;
  }

  ref WidgetBuilder border(
    ColorF color,
    float width = 1.0f,
    Border.Style style = Border.Style.rect,
    float cornerRadius = 0.0f
  ) return {
    widget.withBorder(color, width, style, cornerRadius);
    return this;
  }

  ref WidgetBuilder text(
    string caption,
    ColorF color = ColorF(1, 1, 1, 1),
    float fontSize = defaultFontPtSize,
    TextLabel.Alignment align_ = TextLabel.Alignment.left
  ) return {
    widget.withText(caption, color, fontSize, align_);
    return this;
  }

  ref WidgetBuilder flex(
    FlexDirection dir = FlexDirection.row,
    float gap = 0.0f,
    JustifyContent justify = JustifyContent.start,
    AlignItems align_ = AlignItems.stretch
  ) return {
    widget.withFlex(dir, gap, justify, align_);
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
    widget.withAnchor(left, top, right, bottom);
    return this;
  }

  ref WidgetBuilder onMouseDown(string eventName) return {
    widget.onMouseDown(eventName);
    return this;
  }

  ref WidgetBuilder clipContents(bool clip = true) return {
    widget.withClipContents(clip);
    return this;
  }

  ref WidgetBuilder clipChildren(bool clip = true) return {
    widget.withClipChildren(clip);
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
  return new Widget(parent, rect)
    .withFlex(FlexDirection.row, gap, justify, align_);
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
  return new Widget(parent, rect)
    .withFlex(FlexDirection.column, gap, justify, align_);
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
        .text("Child 1", ColorF(1, 1, 1, 1))
        .onMouseDown("child1Click");
    })
    .child(RectF(0, 0, 120, 40), (ref WidgetBuilder b) {
      b.autoSize()
        .text("Child 2", ColorF(1, 1, 1, 1));
    })
    .build();

  assert(root !is null);
  assert(root.children.length == 2);
  assert(root.components.flexContainer !is null);
  assert(root.components.flexContainer.gap == 12.0f);
  assert(root.children[0].components.textLabel.caption == "Child 1");
  assert(root.children[0].components.mouseEvent.mouseDown == "child1Click");
  assert(root.children[1].components.textLabel.caption == "Child 2");

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
