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
  auto card = new Widget(parent, rect);
  card.components.background = new Background(
    ColorF(0.13f, 0.15f, 0.18f, 1.0f),
    Background.Style.round
  );
  card.components.background.cornerRadius = 8.0f;
  card.components.border = new Border(
    ColorF(0.25f, 0.28f, 0.35f, 1.0f),
    Border.Style.rect
  );
  card.components.border.width = 1.0f;

  auto titleWidget = new Widget(card, RectF(12, 10, rect.width - 24, 20));
  titleWidget.components.textLabel = new TextLabel(
    title,
    ColorF(0.95f, 0.95f, 0.95f, 1.0f)
  );

  return card;
}
