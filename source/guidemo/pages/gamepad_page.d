/**
 * gamepad_page.d - Page 11 showcase rendering a 600x400 vector gamepad
 * using `Path2d.fromSvgPath`, `colorFromString`, and `FillStyle.solidFromString`.
 */
module guidemo.pages.gamepad_page;

import guidemo.common : makeSectionCard;
import guidemo.model : GamepadPageModel;
import yguilib.model : ModelTracker;
import yguilib.render : Renderer;
import yguilib.render.canvas : Canvas;
import yguilib.render.canvas.path2d : Path2d;
import yguilib.render.canvas.types : FillStyle, LineCap, LineJoin, StrokeStyle;
import yguilib.render.render_types : PointF, RectF, colorFromString;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Border;

/// Page 11 widget container showcasing SVG Path2d and color helpers.
final class GamepadPage {
  @disable this();

  /// Constructs GamepadPage with an externally created `modelTracker`.
  this(
    UiSystem ui,
    Widget parent,
    ref ModelTracker!GamepadPageModel modelTracker
  ) {
    assert(ui !is null, "UiSystem must not be null");
    assert(parent !is null, "parent must not be null");
    this.ui = ui;
    tracker = ModelTracker!GamepadPageModel.from(modelTracker);
    root = new Widget(ui.nextWidgetId());
    root.name = "gamepadPage";
    root.rect = RectF(0, 0, 1280, 720);
    parent.addChild(root);

    buildPaths();
    buildSection();
  }

  invariant {
    assert(root !is null);
    assert(canvasWidget !is null);
  }

  /// Syncs page state from the model.
  void update() {
    tracker.update();
  }

  /// Returns the status bar text for this page.
  string formatStatus() {
    return "Path2d SVG & color helpers (600x400)";
  }

  /// Returns the page root widget.
  Widget rootWidget() {
    return root;
  }

  /// Returns the 600x400 gamepad canvas widget.
  Widget drawWidget() {
    return canvasWidget;
  }

  /// Returns whether the page is visible.
  bool visible() const {
    return root.visible;
  }

private:
  struct FaceButton {
    Path2d path;
    FillStyle fill;
  }

  struct AnalogStick {
    Path2d socket;
    Path2d cap;
  }

  void buildSection() {
    auto card = makeSectionCard(
      ui,
      root,
      RectF(20, 68, 1240, 572),
      "Canvas 2D Gamepad Vector",
      "gamepadCard"
    );

    canvasWidget = WidgetBuilder.make(ui)
      .parent(card)
      .name("gamepadCanvas")
      .rect(RectF(320, 98, 600, 400))
      .roundBg(colorFromString("#12141a"))
      .bgRadius(12.0f)
      .border(colorFromString("#2d3342"))
      .borderStyle(Border.Style.roundDashed)
      .borderRadius(12.0f)
      .borderWidth(1.0f)
      .borderDashLen(6.0f)
      .borderDashGap(4.0f)
      .clipContents(true)
      .onDraw(&drawGamepad)
      .build();
  }

  void buildPaths() {
    import std.math : PI;

    leftBumper = Path2d.fromSvgPath(
      "M 155 112 C 165 88, 225 88, 235 106 Z"
    );
    rightBumper = Path2d.fromSvgPath(
      "M 365 106 C 375 88, 435 88, 445 112 Z"
    );
    bodyPath = Path2d.fromSvgPath(
      "M 190 105 L 410 105 "
        ~ "C 455 105, 485 135, 500 200 "
        ~ "C 515 265, 505 320, 465 325 "
        ~ "C 435 328, 415 295, 395 260 "
        ~ "C 385 242, 370 235, 350 235 "
        ~ "L 250 235 "
        ~ "C 230 235, 215 242, 205 260 "
        ~ "C 185 295, 165 328, 135 325 "
        ~ "C 95 320, 85 265, 100 200 "
        ~ "C 115 135, 145 105, 190 105 Z"
    );

    dpad = new Path2d();
    dpad.roundRect(RectF(180, 145, 20, 60), 4);
    dpad.roundRect(RectF(160, 165, 60, 20), 4);

    dpadCenter = new Path2d();
    dpadCenter.arc(PointF(190, 175), 5, 0, 2 * PI, false);

    static immutable float[4] btnX = [410, 435, 410, 385];
    static immutable float[4] btnY = [150, 175, 200, 175];
    static immutable string[4] btnColors = [
      "#f59e0b", "#ef4444", "#10b981", "#3b82f6"
    ];
    foreach (i; 0 .. 4) {
      auto p = new Path2d();
      p.arc(PointF(btnX[i], btnY[i]), 11, 0, 2 * PI, false);
      faceButtons[i] = FaceButton(
        p,
        FillStyle.solidFromString(btnColors[i])
      );
    }

    static immutable float[2] stickX = [248, 352];
    foreach (i; 0 .. 2) {
      auto socket = new Path2d();
      socket.arc(PointF(stickX[i], 212), 24, 0, 2 * PI, false);
      auto cap = new Path2d();
      cap.arc(PointF(stickX[i], 212), 16, 0, 2 * PI, false);
      sticks[i] = AnalogStick(socket, cap);
    }

    menuButtons = new Path2d();
    menuButtons.roundRect(RectF(268, 152, 18, 7), 3.5f);
    menuButtons.roundRect(RectF(314, 152, 18, 7), 3.5f);

    homeButton = new Path2d();
    homeButton.arc(PointF(300, 178), 9, 0, 2 * PI, false);
  }

  void drawGamepad(Renderer r, in Widget w) {
    Canvas c = r.canvas();
    c.lineJoin(LineJoin.round);
    c.lineCap(LineCap.round);

    // 1. Shoulder bumpers (L1 / R1)
    c.fillStyle(FillStyle.solidFromString("#1f2430"));
    c.fill(leftBumper);
    c.fill(rightBumper);

    // 2. Main ergonomic body
    c.fillStyle(FillStyle.solidFromString("#2b3140"));
    c.strokeStyle(StrokeStyle.solidFromString("#4b556b"));
    c.lineWidth(4);
    c.fill(bodyPath);
    c.stroke(bodyPath);

    // 3. D-Pad (left) and center indent
    c.fillStyle(FillStyle.solidFromString("#151821"));
    c.fill(dpad);
    c.fillStyle(FillStyle.solidFromString("#2b3140"));
    c.fill(dpadCenter);

    // 4. Face buttons (right)
    foreach (ref btn; faceButtons) {
      c.fillStyle(btn.fill);
      c.fill(btn.path);
    }

    // 5. Analog sticks (left & right)
    const FillStyle socketFill = FillStyle.solidFromString("#151821");
    const FillStyle capFill = FillStyle.solidFromString("#3c4457");
    const StrokeStyle capStroke = StrokeStyle.solidFromString("#5a657d");
    foreach (ref stick; sticks) {
      c.fillStyle(socketFill);
      c.fill(stick.socket);
      c.fillStyle(capFill);
      c.strokeStyle(capStroke);
      c.lineWidth(2);
      c.fill(stick.cap);
      c.stroke(stick.cap);
    }

    // 6. Center menu / home buttons
    c.fillStyle(FillStyle.solidFromString("#64748b"));
    c.fill(menuButtons);

    c.fillStyle(FillStyle.solidFromString("#151821"));
    c.strokeStyle(StrokeStyle.solidFromString("#64748b"));
    c.lineWidth(2);
    c.fill(homeButton);
    c.stroke(homeButton);
  }

  UiSystem ui;
  ModelTracker!GamepadPageModel tracker;
  Widget root;
  Widget canvasWidget;

  Path2d leftBumper;
  Path2d rightBumper;
  Path2d bodyPath;
  Path2d dpad;
  Path2d dpadCenter;
  FaceButton[4] faceButtons;
  AnalogStick[2] sticks;
  Path2d menuButtons;
  Path2d homeButton;
}

unittest {
  import yguilib.uisystem : makeHeadlessUiSystem;

  auto ui = makeHeadlessUiSystem();
  auto parent = new Widget(ui.nextWidgetId());
  parent.name = "testParent";
  auto tracker = ModelTracker!GamepadPageModel(new GamepadPageModel());
  auto page = new GamepadPage(ui, parent, tracker);

  void verifyAllNamed(Widget w) {
    assert(w.name.length > 0, "Widget missing name");
    foreach (child; w.children) {
      verifyAllNamed(child);
    }
  }
  verifyAllNamed(page.rootWidget());
  assert(page.drawWidget().rect == RectF(320, 98, 600, 400));
  assert(page.formatStatus() == "Path2d SVG & color helpers (600x400)");

  void checkPathInCanvas(const Path2d p) {
    assert(p !is null);
    assert(!p.isEmpty());
    const RectF b = p.bounds();
    assert(b.width > 0 && b.height > 0);
    assert(b.x >= 0 && b.y >= 0);
    assert(b.x + b.width <= 600 && b.y + b.height <= 400);
  }

  checkPathInCanvas(page.leftBumper);
  checkPathInCanvas(page.rightBumper);
  checkPathInCanvas(page.bodyPath);
  checkPathInCanvas(page.dpad);
  checkPathInCanvas(page.dpadCenter);
  foreach (ref btn; page.faceButtons) {
    checkPathInCanvas(btn.path);
  }
  foreach (ref stick; page.sticks) {
    checkPathInCanvas(stick.socket);
    checkPathInCanvas(stick.cap);
  }
  checkPathInCanvas(page.menuButtons);
  checkPathInCanvas(page.homeButton);
}
