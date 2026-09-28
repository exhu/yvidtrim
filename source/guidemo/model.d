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

  bool quitRequested = false;
}
