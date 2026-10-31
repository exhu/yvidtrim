/**
 * tab_button.d - Factory and state management for header tab buttons.
 */
module guidemo.tab_button;

import yguilib.render.render_types : ColorF, RectF;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : TextLabel;

/// Default visual dimensions and font metrics for header tab buttons.
enum defaultTabButtonWidth = 175.0f;
enum defaultTabButtonHeight = 30.0f;
enum defaultTabButtonRadius = 4.0f;
enum defaultTabButtonFontSize = 13.0f;

/// Visual colors for active and inactive tab buttons.
enum tabActiveBg = ColorF(0.20f, 0.45f, 0.85f, 1.0f);
enum tabActiveBorder = ColorF(0.40f, 0.70f, 1.0f, 1.0f);
enum tabActiveText = ColorF(1.0f, 1.0f, 1.0f, 1.0f);

enum tabInactiveBg = ColorF(0.16f, 0.18f, 0.23f, 1.0f);
enum tabInactiveBorder = ColorF(0.30f, 0.35f, 0.45f, 1.0f);
enum tabInactiveText = ColorF(0.80f, 0.85f, 0.95f, 1.0f);

/**
 * Creates a styled tab button inside the specified parent container.
 *
 * Params:
 *   parent = Parent container widget (must not be null).
 *   label = Text caption displayed on the button.
 *   eventName = Event name emitted on mouse down (e.g., "tab1Btn").
 *   isActive = Whether the button initializes in the active highlight state.
 *   width = Desired fixed button width.
 *   height = Desired fixed button height.
 *
 * Returns:
 *   Configured tab button widget.
 */
Widget createTabButton(
  Widget parent,
  string label,
  string eventName,
  bool isActive = false,
  float width = defaultTabButtonWidth,
  float height = defaultTabButtonHeight
) {
  assert(parent !is null, "parent must not be null");

  const ColorF bgCol = isActive ? tabActiveBg : tabInactiveBg;
  const ColorF borderCol = isActive
    ? tabActiveBorder
    : tabInactiveBorder;
  const ColorF textCol = isActive ? tabActiveText : tabInactiveText;

  return WidgetBuilder(parent, RectF(0, 0, width, height))
    .fixedSize(width, height)
    .padding(5, 8, 5, 8)
    .roundBackground(bgCol, defaultTabButtonRadius)
    .border(borderCol, 1.0f)
    .text(label, textCol, defaultTabButtonFontSize, TextLabel.Alignment.center)
    .onMouseDown(eventName)
    .build();
}

/**
 * Updates visual styling (background, border, text color) for a tab button.
 *
 * Params:
 *   btn = Tab button widget to update (must not be null).
 *   isActive = True if the button represents the active page.
 */
void updateTabButtonState(Widget btn, bool isActive) {
  assert(btn !is null, "btn must not be null");
  btn.setBackgroundColor(isActive ? tabActiveBg : tabInactiveBg);
  btn.setBorderColor(isActive ? tabActiveBorder : tabInactiveBorder);
  btn.setTextColor(isActive ? tabActiveText : tabInactiveText);
}

unittest {
  auto root = new Widget(null, RectF(0, 0, 800, 600));

  // 1. Create active tab button
  auto btnActive = createTabButton(root, "Active Tab", "tabActive", true);
  assert(btnActive !is null);
  assert(btnActive.rect.width == defaultTabButtonWidth);
  assert(btnActive.rect.height == defaultTabButtonHeight);
  assert(btnActive.components.background !is null);
  assert(btnActive.components.background.color == tabActiveBg);
  assert(btnActive.components.border !is null);
  assert(btnActive.components.border.color == tabActiveBorder);
  assert(btnActive.components.textLabel !is null);
  assert(btnActive.components.textLabel.caption == "Active Tab");
  assert(btnActive.components.textLabel.color == tabActiveText);

  // 2. Create inactive tab button
  auto btnInactive = createTabButton(
    root,
    "Inactive Tab",
    "tabInactive",
    false
  );
  assert(btnInactive !is null);
  assert(btnInactive.components.background.color == tabInactiveBg);
  assert(btnInactive.components.border.color == tabInactiveBorder);
  assert(btnInactive.components.textLabel.color == tabInactiveText);

  // 3. Update states
  updateTabButtonState(btnActive, false);
  assert(btnActive.components.background.color == tabInactiveBg);
  assert(btnActive.components.border.color == tabInactiveBorder);
  assert(btnActive.components.textLabel.color == tabInactiveText);

  updateTabButtonState(btnInactive, true);
  assert(btnInactive.components.background.color == tabActiveBg);
  assert(btnInactive.components.border.color == tabActiveBorder);
  assert(btnInactive.components.textLabel.color == tabActiveText);
}

unittest {
  import yguilib.widget.layout_components : AlignItems, FlexDirection,
    JustifyContent, SizingMode;

  auto root = new Widget(null, RectF(0, 0, 800, 600));
  auto row = WidgetBuilder(root, RectF(0, 0, 500, 40))
    .flex(
      FlexDirection.row,
      10.0f,
      JustifyContent.start,
      AlignItems.center
    )
    .build();

  auto b1 = createTabButton(row, "Tab 1", "t1", true);
  auto b2 = createTabButton(row, "Tab 2", "t2", false);

  assert(row.children.length == 2);
  assert(row.children[0] is b1);
  assert(row.children[1] is b2);

  assert(b1.components.size !is null);
  assert(b1.components.size.width.value == defaultTabButtonWidth);
  assert(b1.components.size.width.mode == SizingMode.fixed);
  assert(b1.components.size.height.value == defaultTabButtonHeight);
  assert(b1.components.size.height.mode == SizingMode.fixed);

  assert(b2.components.size !is null);
  assert(b2.components.size.width.value == defaultTabButtonWidth);
  assert(b2.components.size.width.mode == SizingMode.fixed);
  assert(b2.components.size.height.value == defaultTabButtonHeight);
  assert(b2.components.size.height.mode == SizingMode.fixed);
}

version (unittest) {
  void main() {
  }
}
