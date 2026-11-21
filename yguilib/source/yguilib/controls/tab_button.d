/**
 * tab_button.d - Factory and state management for header tab buttons.
 */
module yguilib.controls.tab_button;

import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.layout_components : Insets;

/// Default visual dimensions and font metrics for header tab buttons.
enum defaultTabButtonWidth = 138.0f;
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
 *   label = Text caption displayed on the button (allowed to be null).
 *   eventName = Event name emitted on mouse down, e.g., "tab1Btn" (allowed to
 *     be null).
 *   isActive = Whether the button initializes in the active highlight state.
 *   width = Desired fixed button width.
 *   height = Desired fixed button height.
 *
 * Returns:
 *   Configured tab button widget.
 */
Widget createTabButton(
  UiSystem ui,
  Widget parent,
  string label,
  string eventName,
  bool isActive,
  float width,
  float height,
  string name
) {
  assert(parent !is null, "parent must not be null");

  const ColorF bgCol = isActive ? tabActiveBg : tabInactiveBg;
  const ColorF borderCol = isActive
    ? tabActiveBorder
    : tabInactiveBorder;
  const ColorF textCol = isActive ? tabActiveText : tabInactiveText;
  const string btnName = (name.length > 0) ? name : "tabButton";

  return WidgetBuilder.make(ui)
    .parent(parent)
    .name(btnName)
    .rect(RectF(0, 0, width, height))
    .fixedSize(width, height)
    .padding(Insets(5, 8, 5, 8))
    .roundBg(bgCol)
    .bgRadius(defaultTabButtonRadius)
    .border(borderCol)
    .borderWidth(1.0f)
    .text(label)
    .textColor(textCol)
    .fontSize(defaultTabButtonFontSize)
    .textAlign(TextLabel.Alignment.center)
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
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  auto ui = new UiSystemImpl(null);

  auto root = new Widget(ui.nextWidgetId());
  root.rect = RectF(0, 0, 800, 600);

  // 1. Create active tab button
  auto btnActive = createTabButton(
    ui, root, "Active Tab", "tabActive", true,
    defaultTabButtonWidth, defaultTabButtonHeight, null
  );
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
    ui,
    root,
    "Inactive Tab",
    "tabInactive",
    false,
    defaultTabButtonWidth,
    defaultTabButtonHeight,
    null
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
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.layout_components : AlignItems, FlexDirection,
    JustifyContent, SizingMode;

  auto ui = new UiSystemImpl(null);
  auto root = new Widget(ui.nextWidgetId());
  root.rect = RectF(0, 0, 800, 600);
  auto row = WidgetBuilder.make(ui)
    .parent(root)
    .rect(RectF(0, 0, 500, 40))
    .flexDirection(FlexDirection.row)
    .gap(10.0f)
    .justify(JustifyContent.start)
    .alignItems(AlignItems.center)
    .build();

  auto b1 = createTabButton(
    ui, row, "Tab 1", "t1", true,
    defaultTabButtonWidth, defaultTabButtonHeight, null
  );
  auto b2 = createTabButton(
    ui, row, "Tab 2", "t2", false,
    defaultTabButtonWidth, defaultTabButtonHeight, null
  );

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
