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

/// Canonical order of demo pages in guidemo.
enum DemoPage : size_t {
  layoutPainter,
  textLabel,
  button,
  buttonSystem,
  tabControl,
  scrollbars,
  virtList,
  knob,
}

/// Display metadata for a single guidemo page.
struct DemoPageMeta {
  string tabTitle;
  string statusTitle;
}

/// Ordered metadata table indexed by DemoPage.
immutable DemoPageMeta[DemoPage.max + 1] demoPages = [
  DemoPage.layoutPainter: DemoPageMeta("Layout & Paint", "Layout"),
  DemoPage.textLabel: DemoPageMeta("TextLabel Demo", "TextLabel"),
  DemoPage.button: DemoPageMeta("Hover (Ctrl)", "Hover Buttons"),
  DemoPage.buttonSystem: DemoPageMeta("Hover (System)", "Hover System"),
  DemoPage.tabControl: DemoPageMeta("TabControl", "TabControl"),
  DemoPage.scrollbars: DemoPageMeta("Scrollbars", "Scrollbars"),
  DemoPage.virtList: DemoPageMeta("VirtList", "VirtList"),
  DemoPage.knob: DemoPageMeta("Knob (Lock)", "Knob"),
];

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
  float playgroundBarWidth = 570.0f;
}

/// Model holding Page 7 (VirtList Showcase) state.
final class VirtListPageModel : VersionedModel {
  size_t vItemsCount = 10000;
  size_t vFirstVisible = 0;
  size_t vVisibleCount = 0;
  size_t vActiveWidgets = 0;
  size_t vPooledWidgets = 0;
  size_t hItemsCount = 1200;
  size_t hFirstVisible = 0;
  size_t hVisibleCount = 0;
  size_t hActiveWidgets = 0;
  size_t hPooledWidgets = 0;
  size_t recycledStopsCount = 0;
  size_t activeVideosCount = 0;
  /// Horizontal VirtList viewport width in pixels (set by the controller).
  float hViewportWidth = 583.0f;
}

/// Model holding Page 8 (Knob / cursor lock showcase) state.
final class KnobPageModel : VersionedModel {
  float value = 0.0f;
  bool dragging = false;
}
