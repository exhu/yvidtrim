/**
 * common.d - Shared UI helpers and components for guidemo.
 */
module guidemo.common;

import yguilib.render.render_types : ColorF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Background, Border, TextLabel;

/// Factory function to create standard section cards across all demo pages.
Widget makeSectionCard(
  Widget parent,
  RectF rect,
  string title
) {
  auto card = WidgetBuilder(parent, rect)
    .roundBackground(ColorF(0.13f, 0.15f, 0.18f, 1.0f), 8.0f)
    .border(ColorF(0.25f, 0.28f, 0.35f, 1.0f), 1.0f)
    .build();

  WidgetBuilder(card, RectF(12, 10, rect.width - 24, 20))
    .text(title, ColorF(0.95f, 0.95f, 0.95f, 1.0f))
    .build();

  return card;
}
