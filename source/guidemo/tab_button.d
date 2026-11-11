/**
 * tab_button.d - Factory and state management for header tab buttons.
 */
module guidemo.tab_button;

import guidemo.model : HeaderTabsModel;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.data_components : WidgetArrayProvider;
import yguilib.widget.drawing_components : TextLabel;

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

  return WidgetBuilder(ui.nextWidgetId())
    .parent(parent)
    .rect(RectF(0, 0, width, height))
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

/**
 * Data-driven widget provider creating and updating header tab buttons
 * for a WidgetArrayComponent.
 */
final class HeaderTabButtonsProvider : WidgetArrayProvider {
  this(UiSystem ui, const(HeaderTabsModel) model) {
    assert(ui !is null, "ui must not be null");
    assert(model !is null, "model must not be null");
    this.ui = ui;
    this.model = model;
  }

  invariant {
    assert(model !is null);
    assert(ui !is null);
  }

  override void addWidget(Widget parent) {
    assert(parent !is null, "parent must not be null");
    createTabButton(ui, parent, null, null);
  }

  override void updateWidgetAt(Widget w, size_t index) {
    import std.format : format;

    assert(w !is null, "w must not be null");
    assert(index < model.tabNames.length, "tab index out of bounds");
    assert(w.components.mouseEvent !is null);

    w.setCaption(model.tabNames[index]);
    w.components.mouseEvent.mouseDown = format("tab%dBtn", index + 1);
    updateTabButtonState(w, index == model.activeTab);
  }

private:
  UiSystem ui;
  const(HeaderTabsModel) model;
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  auto ui = new UiSystemImpl(null);

  auto root = new Widget(ui.nextWidgetId());
  root.rect = RectF(0, 0, 800, 600);

  // 1. Create active tab button
  auto btnActive = createTabButton(ui, root, "Active Tab", "tabActive", true);
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
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.layout_components : AlignItems, FlexDirection,
    JustifyContent, SizingMode;

  auto ui = new UiSystemImpl(null);
  auto root = new Widget(ui.nextWidgetId());
  root.rect = RectF(0, 0, 800, 600);
  auto row = WidgetBuilder(ui.nextWidgetId())
    .parent(root)
    .rect(RectF(0, 0, 500, 40))
    .flex(
      FlexDirection.row,
      10.0f,
      JustifyContent.start,
      AlignItems.center
    )
    .build();

  auto b1 = createTabButton(ui, row, "Tab 1", "t1", true);
  auto b2 = createTabButton(ui, row, "Tab 2", "t2", false);

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

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
  auto tabsModel = new HeaderTabsModel();
  auto provider = new HeaderTabButtonsProvider(ui, tabsModel);
  auto container = new Widget(ui.nextWidgetId());
  container.rect = RectF(0, 0, 730, 30);

  foreach (_; 0 .. tabsModel.tabNames.length) {
    provider.addWidget(container);
  }
  assert(container.children.length == tabsModel.tabNames.length);

  foreach (i, child; container.children) {
    provider.updateWidgetAt(child, i);
  }

  assert(container.children[0].components.textLabel.caption ==
    "[1] Layout & Paint");
  assert(container.children[0].components.mouseEvent.mouseDown == "tab1Btn");
  assert(container.children[0].components.background.color == tabActiveBg);

  assert(container.children[1].components.textLabel.caption ==
    "[2] TextLabel Demo");
  assert(container.children[1].components.mouseEvent.mouseDown == "tab2Btn");
  assert(container.children[1].components.background.color == tabInactiveBg);

  assert(container.children[3].components.textLabel.caption ==
    "[4] Hover (System)");
  assert(container.children[3].components.mouseEvent.mouseDown == "tab4Btn");
  assert(container.children[3].components.background.color == tabInactiveBg);

  // Switch active tab to index 2 and re-update
  tabsModel.edit();
  tabsModel.activeTab = 2;
  tabsModel.commit();
  foreach (i, child; container.children) {
    provider.updateWidgetAt(child, i);
  }
  assert(container.children[0].components.background.color == tabInactiveBg);
  assert(container.children[2].components.background.color == tabActiveBg);
}

version (unittest) {
  void main() {
  }
}
