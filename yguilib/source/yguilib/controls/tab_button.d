/**
 * tab_button.d - Factory and state management for header tab buttons.
 */
module yguilib.controls.tab_button;

import yguilib.controls.common : ButtonFace, WidgetColors, applyColors,
  orDefault, styledButton;
import yguilib.controls.tooltip : Tooltip;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
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

/// Color triplets for active and inactive tab button states.
enum tabActiveColors = WidgetColors(
  tabActiveBg,
  tabActiveBorder,
  tabActiveText
);
enum tabInactiveColors = WidgetColors(
  tabInactiveBg,
  tabInactiveBorder,
  tabInactiveText
);

/// Visual styling and sizing configuration for tab buttons.
struct TabButtonStyle {
  float width = defaultTabButtonWidth;
  float height = defaultTabButtonHeight;
  float cornerRadius = defaultTabButtonRadius;
  float fontSize = defaultTabButtonFontSize;
  Insets padding = Insets(5, 8, 5, 8);
  WidgetColors active = tabActiveColors;
  WidgetColors inactive = tabInactiveColors;
}

/**
 * Creates a styled tab button inside the specified parent container.
 *
 * Params:
 *   ui = Active UiSystem (must not be null).
 *   parent = Parent container widget (must not be null).
 *   label = Text caption displayed on the button (allowed to be null).
 *   eventName = Event name emitted on mouse down, e.g., "tab1Btn" (allowed to
 *     be null).
 *   isActive = Whether the button initializes in the active highlight state.
 *   style = Visual styling and sizing configuration.
 *   name = Optional widget name (defaults to "tabButton" when null/empty).
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
  in TabButtonStyle style,
  string name
) {
  assert(ui !is null, "ui must not be null");
  assert(parent !is null, "parent must not be null");

  ButtonFace face;
  face.colors = isActive ? style.active : style.inactive;
  face.width = style.width;
  face.height = style.height;
  face.cornerRadius = style.cornerRadius;
  face.borderWidth = 1.0f;
  face.fontSize = style.fontSize;
  face.padding = style.padding;

  const string btnName = orDefault(name, "tabButton");
  return styledButton(ui, parent, btnName, label, face)
    .onMouseDown(eventName)
    .component(new Tooltip())
    .build();
}

/**
 * Updates visual styling (background, border, text color) for a tab button.
 *
 * Params:
 *   btn = Tab button widget to update (must not be null).
 *   isActive = True if the button represents the active page.
 *   style = Visual styling providing active and inactive color palettes.
 */
void updateTabButtonState(
  Widget btn,
  bool isActive,
  in TabButtonStyle style
) {
  assert(btn !is null, "btn must not be null");
  applyColors(btn, isActive ? style.active : style.inactive);
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  auto ui = new UiSystemImpl(null);

  auto root = new Widget(ui.nextWidgetId());
  root.rect = RectF(0, 0, 800, 600);
  TabButtonStyle style;

  // 1. Create active tab button
  auto btnActive = createTabButton(
    ui, root, "Active Tab", "tabActive", true, style, null
  );
  assert(btnActive !is null);
  assert(btnActive.name == "tabButton");
  assert(btnActive.rect.width == defaultTabButtonWidth);
  assert(btnActive.rect.height == defaultTabButtonHeight);
  assert(btnActive.components.background !is null);
  assert(btnActive.components.background.color == tabActiveBg);
  assert(btnActive.components.border !is null);
  assert(btnActive.components.border.color == tabActiveBorder);
  assert(btnActive.components.textLabel !is null);
  assert(btnActive.components.textLabel.caption == "Active Tab");
  assert(btnActive.components.textLabel.color == tabActiveText);
  assert(btnActive.components.has!Tooltip());
  assert(
    btnActive.components.get!Tooltip().resolveText(btnActive) == "Active Tab"
  );

  // 2. Create inactive tab button with custom name
  auto btnInactive = createTabButton(
    ui,
    root,
    "Inactive Tab",
    "tabInactive",
    false,
    style,
    "customTab"
  );
  assert(btnInactive !is null);
  assert(btnInactive.name == "customTab");
  assert(btnInactive.components.background.color == tabInactiveBg);
  assert(btnInactive.components.border.color == tabInactiveBorder);
  assert(btnInactive.components.textLabel.color == tabInactiveText);

  // 3. Update states
  updateTabButtonState(btnActive, false, style);
  assert(btnActive.components.background.color == tabInactiveBg);
  assert(btnActive.components.border.color == tabInactiveBorder);
  assert(btnActive.components.textLabel.color == tabInactiveText);

  updateTabButtonState(btnInactive, true, style);
  assert(btnInactive.components.background.color == tabActiveBg);
  assert(btnInactive.components.border.color == tabActiveBorder);
  assert(btnInactive.components.textLabel.color == tabActiveText);
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.builder : WidgetBuilder;
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

  TabButtonStyle style;
  auto b1 = createTabButton(
    ui, row, "Tab 1", "t1", true, style, null
  );
  auto b2 = createTabButton(
    ui, row, "Tab 2", "t2", false, style, null
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
