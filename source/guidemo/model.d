/**
 * model.d - State model for guidemo application.
 */
module guidemo.model;

import yguilib.model : VersionedModel;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.layout_components : AlignItems, FlexDirection,
  JustifyContent;

/// Debug draw visualization mode cycled via F12.
enum DebugDrawMode {
  off,
  allVisible,
  allWithHidden,
  activePageVisible,
  activePageWithHidden,
}

/// Model holding shared global state for the demo.
final class DemoModel : VersionedModel {
  size_t activePage = 0;
  DebugDrawMode debugDrawMode = DebugDrawMode.off;
  bool quitRequested = false;
  string statusText = "";
}

/// Model holding Page 1 (Layout & Painter) state.
final class LayoutPainterPageModel : VersionedModel {
  JustifyContent justify = JustifyContent.start;
  AlignItems alignItems = AlignItems.stretch;
  FlexDirection direction = FlexDirection.row;
  float gap = 8.0f;
  bool child2Visible = true;
  size_t textSampleIndex = 0;
  float alphaValue = 0.2f;
}

/// Model holding Page 2 (TextLabel Playground) state.
final class TextLabelPageModel : VersionedModel {
  bool labelMultiline = true;
  bool labelEllipsis = true;
  TextLabel.Alignment labelAlignment = TextLabel.Alignment.left;
  size_t labelSampleIndex = 0;
}

/// Model holding Page 3 (Hover Button Showcase) state.
final class ButtonPageModel : VersionedModel {
  size_t buttonClickCount = 0;
}

/// Model holding Page 4 (Hover System Showcase) state.
final class ButtonSystemPageModel : VersionedModel {
  size_t buttonClickCount = 0;
}

/// Model holding Page 5 (TabControl Showcase) state.
final class TabControlPageModel : VersionedModel {
  size_t subTab = 0;
  size_t verticalTab = 0;
  size_t dynamicTab = 0;
  size_t dynamicTabCount = 6;
  float viewportWidth = 580.0f;
  string lastEventName = "none";
  size_t lastEventIndex = 0;
}

/// Model holding Page 6 (Scrollbars Showcase) state.
final class ScrollbarsPageModel : VersionedModel {
  long hScroll = 0;
  long vScroll = 0;
  long liveValue = 250;
  size_t liveEventCount = 0;
  long releaseValue = 250;
  size_t releaseEventCount = 0;
  long playgroundValue = 200;
}

/// Default tab captions for the main guidemo header TabControl.
immutable string[] defaultHeaderTabNames = [
  "[1] Layout & Paint",
  "[2] TextLabel Demo",
  "[3] Hover (Ctrl)",
  "[4] Hover (System)",
  "[5] TabControl",
  "[6] Scrollbars",
];

/// Model holding header tab names and active tab index.
final class HeaderTabsModel : VersionedModel {
  string[] tabNames = [
    "[1] Layout & Paint",
    "[2] TextLabel Demo",
    "[3] Hover (Ctrl)",
    "[4] Hover (System)",
    "[5] TabControl",
    "[6] Scrollbars",
  ];
  size_t activeTab = 0;
}
