/**
 * common.d - Shared UI helpers and components for guidemo.
 */
module guidemo.common;

import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Background, Border, TextLabel;

/// Returns true if `ev` matches `targetKey` (case-insensitive for ASCII
/// letters) or `targetScan`.
bool isKey(in AppEvent ev, Keycode targetKey, Scancode targetScan) {
  if (ev.keyData.scancode == targetScan) {
    return true;
  }
  if (ev.keyData.key == targetKey) {
    return true;
  }
  // Handle potential uppercase ASCII keycode
  if (targetKey >= 'a' && targetKey <= 'z') {
    if (ev.keyData.key == (targetKey - 32)) {
      return true;
    }
  }
  return false;
}

/// Factory function to create standard section cards across all demo pages.
Widget makeSectionCard(
  UiSystem ui,
  Widget parent,
  RectF rect,
  string title,
  string name = null
) {
  const string cardName = (name.length > 0) ? name : "sectionCard";
  auto card = WidgetBuilder.make(ui)
    .parent(parent)
    .name(cardName)
    .rect(rect)
    .roundBg(ColorF(0.13f, 0.15f, 0.18f, 1.0f))
    .bgRadius(8.0f)
    .border(ColorF(0.25f, 0.28f, 0.35f, 1.0f))
    .borderWidth(1.0f)
    .build();

  WidgetBuilder.make(ui)
    .parent(card)
    .name(cardName ~ "Title")
    .rect(RectF(12, 10, rect.width - 24, 20))
    .text(title)
    .textColor(ColorF(0.95f, 0.95f, 0.95f, 1.0f))
    .build();

  return card;
}
