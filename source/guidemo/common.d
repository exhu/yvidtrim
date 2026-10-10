/**
 * common.d - Shared UI helpers and components for guidemo.
 */
module guidemo.common;

import yguilib.render.render_types : ColorF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.drawing_components : Background, Border, TextLabel;

/// Factory function to create standard section cards across all demo pages.
Widget makeSectionCard(
  Widget parent,
  RectF rect,
  string title
) {
  auto card = new Widget(parent, rect)
    .withRoundBackground(ColorF(0.13f, 0.15f, 0.18f, 1.0f), 8.0f)
    .withBorder(ColorF(0.25f, 0.28f, 0.35f, 1.0f), 1.0f);

  new Widget(card, RectF(12, 10, rect.width - 24, 20))
    .withText(title, ColorF(0.95f, 0.95f, 0.95f, 1.0f));

  return card;
}
