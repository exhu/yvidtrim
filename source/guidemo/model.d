/**
 * model.d - State model for guidemo application.
 */
module guidemo.model;

import yguilib.model : VersionedModel;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.layout_components : AlignItems, FlexDirection,
  JustifyContent;

/// Model holding interactive state for the demo.
final class DemoModel : VersionedModel {
  size_t activePage = 0;

  // Page 1 state (Layout & Painter)
  JustifyContent justify = JustifyContent.start;
  AlignItems alignItems = AlignItems.stretch;
  FlexDirection direction = FlexDirection.row;
  float gap = 8.0f;
  bool child2Visible = true;
  size_t textSampleIndex = 0;
  float alphaValue = 0.8f;
  float alphaStep = 0.015f;

  // Page 2 state (TextLabel Playground)
  bool labelMultiline = true;
  bool labelEllipsis = true;
  TextLabel.Alignment labelAlignment = TextLabel.Alignment.left;
  size_t labelSampleIndex = 0;

  // Page 3 state (Hover Button Showcase)
  size_t buttonClickCount = 0;

  // Page 5 state (TabControl Showcase)
  size_t page5SubTab = 0;
  size_t page5VerticalTab = 0;
  size_t page5DynamicTab = 0;
  size_t page5DynamicTabCount = 6;
  float page5ViewportWidth = 580.0f;
  string page5LastEventName = "none";
  size_t page5LastEventIndex = 0;

  bool quitRequested = false;
}

/// Default tab captions for the main guidemo header TabControl.
immutable string[] defaultHeaderTabNames = [
  "[1] Layout & Paint",
  "[2] TextLabel Demo",
  "[3] Hover (Ctrl)",
  "[4] Hover (System)",
  "[5] TabControl",
];

/// Model holding header tab names and active tab index.
final class HeaderTabsModel : VersionedModel {
  string[] tabNames = [
    "[1] Layout & Paint",
    "[2] TextLabel Demo",
    "[3] Hover (Ctrl)",
    "[4] Hover (System)",
    "[5] TabControl",
  ];
  size_t activeTab = 0;
}
