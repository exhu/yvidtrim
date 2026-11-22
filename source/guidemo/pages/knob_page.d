/**
 * knob_page.d - Page 8 showcase for a "drag value" knob using
 * CursorCapture.lock (hidden cursor, unbounded relative deltas).
 */
module guidemo.pages.knob_page;

import guidemo.common : makeSectionCard;
import guidemo.model : KnobPageModel;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.input_components : CursorCapture;

/// View event names emitted by the Page 8 drag value box.
enum knobDownEvent = "knobDown";
enum knobDragEvent = "knobDrag";
enum knobUpEvent = "knobUp";

/// Page 8 widget container showcasing a cursor-locked drag value box.
final class KnobPage {
  @disable this();

  /// Constructs KnobPage with an externally created `modelTracker`.
  this(
    UiSystem ui,
    Widget parent,
    ref ModelTracker!KnobPageModel modelTracker
  ) {
    assert(ui !is null, "UiSystem must not be null");
    assert(parent !is null, "parent must not be null");
    this.ui = ui;
    tracker = ModelTracker!KnobPageModel.from(modelTracker);
    root = new Widget(ui.nextWidgetId());
    root.name = "knobPage";
    root.rect = RectF(0, 0, 1280, 720);
    parent.addChild(root);

    buildDragValueSection();
  }

  invariant {
    assert(root !is null);
  }

  /// Syncs the value label and drag highlight from the model.
  void update() {
    if (!tracker.update()) {
      return;
    }
    valueLabel.setCaption(formatValue());
  }

  /// Returns the formatted knob value shown in the drag box.
  string formatValue() {
    import std.format : format;

    const auto m = tracker.model;
    return format("%.2f%s", m.value, m.dragging ? "  (dragging)" : "");
  }

  /// Returns the status bar text for this page.
  string formatStatus() {
    import std.format : format;

    return format("Value: %.2f", tracker.model.value);
  }

  /// Returns the page root widget.
  Widget rootWidget() {
    return root;
  }

  /// Returns the widget displaying the knob value.
  Widget valueBox() {
    return valueBoxWidget;
  }

  /// Returns whether the page is visible.
  bool isVisible() const {
    return root.visible;
  }

private:
  void buildDragValueSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(20, 68, 605, 280),
      "1. Drag Value Box (CursorCapture.lock)",
      "knobCard"
    );

    valueBoxWidget = WidgetBuilder.make(ui)
      .parent(card)
      .name("knobValueBox")
      .rect(RectF(16, 44, 240, 48))
      .roundBg(ColorF(0.10f, 0.16f, 0.24f, 1.0f))
      .bgRadius(6.0f)
      .border(ColorF(0.35f, 0.60f, 0.95f, 1.0f))
      .borderWidth(1.0f)
      .onMouseDown(knobDownEvent)
      .onMouseDrag(knobDragEvent, CursorCapture.lock)
      .onMouseUp(knobUpEvent)
      .build();

    valueLabel = WidgetBuilder.make(ui)
      .parent(valueBoxWidget)
      .name("knobValueLabel")
      .rect(RectF(0, 14, 240, 20))
      .text(formatValue())
      .textColor(ColorF(0.95f, 0.90f, 0.40f, 1.0f))
      .fontSize(16.0f)
      .textAlign(TextLabel.Alignment.center)
      .build();

    WidgetBuilder.make(ui)
      .parent(card)
      .name("knobHelpLabel")
      .rect(RectF(16, 108, 570, 150))
      .text(
        "- Press and drag horizontally on the box to change the value\n" ~
          "  (0.01 per pixel of relative motion).\n" ~
          "- The cursor is hidden while dragging; motion is unbounded\n" ~
          "  (window and screen edges do not stop it).\n" ~
          "- On release the cursor returns to the press point.\n" ~
          "- Vertical drag is ignored."
      )
      .textColor(ColorF(0.74f, 0.80f, 0.88f, 1.0f))
      .fontSize(13.0f)
      .multiline(true)
      .build();
  }

  UiSystem ui;
  ModelTracker!KnobPageModel tracker;
  Widget root;
  Widget valueBoxWidget;
  Widget valueLabel;
}
