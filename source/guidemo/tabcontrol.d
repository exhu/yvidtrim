/**
 * tabcontrol.d - Reusable model-driven TabControl widget tree, view, and
 * controller.
 */
module guidemo.tabcontrol;

import guidemo.tab_button : defaultTabButtonFontSize, defaultTabButtonHeight,
  defaultTabButtonRadius, defaultTabButtonWidth, tabActiveBg, tabActiveBorder,
  tabActiveText, tabInactiveBg, tabInactiveBorder, tabInactiveText;
import yguilib.controller : HandleResult;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker, VersionedModel;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.data_components : WidgetArrayProvider;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.layout_components : AlignItems, FlexDirection,
  JustifyContent;
import yguilib.widget.widget_view : WidgetView, WidgetViewBase,
  WidgetViewControllerBase;

/// Internal mouseDown event name emitted by individual tab button children
/// before translation by TabControlWidgetView.
enum tabButtonMouseDownEvent = "tabBtnDown";

/// Default view event name emitted by TabControl when none is specified.
enum defaultTabControlEventName = "pageTabSwitch";

/// Registered name of TabControlWidgetView in UiRegistry.
enum tabControlWidgetViewName = "TabControlWidgetView";

/// Registered name of TabControlWidgetViewController in UiRegistry.
enum tabControlWidgetViewControllerName = "TabControlWidgetViewController";

/// Versioned model holding tab button captions and the currently active tab.
final class TabsModel : VersionedModel {
  string[] tabNames;
  size_t activeTab = 0;

  this() {
  }

  /// Constructs TabsModel with initial tab captions (`names` allowed to be
  /// null/empty) and active index.
  this(string[] names, size_t initialActiveTab = 0) {
    this.tabNames = names.dup;
    this.activeTab = initialActiveTab;
  }
}

/// Visual styling and sizing configuration for buttons inside a TabControl.
struct TabControlStyle {
  float buttonWidth = defaultTabButtonWidth;
  float buttonHeight = defaultTabButtonHeight;
  float cornerRadius = defaultTabButtonRadius;
  float fontSize = defaultTabButtonFontSize;

  ColorF activeBg = tabActiveBg;
  ColorF activeBorder = tabActiveBorder;
  ColorF activeText = tabActiveText;

  ColorF inactiveBg = tabInactiveBg;
  ColorF inactiveBorder = tabInactiveBorder;
  ColorF inactiveText = tabInactiveText;
}

/**
 * WidgetArrayProvider creating and updating styled tab buttons synchronized
 * with a TabsModel.
 */
final class TabButtonsProvider : WidgetArrayProvider {
  this(const(TabsModel) model, in TabControlStyle style = TabControlStyle()) {
    assert(model !is null, "model must not be null");
    this.model = model;
    this.style = style;
  }

  invariant {
    assert(model !is null);
  }

  override void addWidget(Widget parent) {
    assert(parent !is null, "parent must not be null");
    WidgetBuilder(parent, RectF(0, 0, style.buttonWidth, style.buttonHeight))
      .fixedSize(style.buttonWidth, style.buttonHeight)
      .padding(5, 8, 5, 8)
      .roundBackground(style.inactiveBg, style.cornerRadius)
      .border(style.inactiveBorder, 1.0f)
      .text(
        null,
        style.inactiveText,
        style.fontSize,
        TextLabel.Alignment.center
      )
      .onMouseDown(tabButtonMouseDownEvent)
      .build();
  }

  override void updateWidgetAt(Widget w, size_t index) {
    assert(w !is null, "w must not be null");
    assert(index < model.tabNames.length, "tab index out of bounds");
    assert(w.components.mouseEvent !is null);

    const bool isActive = (index == model.activeTab);
    w.setCaption(model.tabNames[index]);
    w.components.mouseEvent.mouseDown = tabButtonMouseDownEvent;
    w.setBackgroundColor(isActive ? style.activeBg : style.inactiveBg);
    w.setBorderColor(isActive ? style.activeBorder : style.inactiveBorder);
    w.setTextColor(isActive ? style.activeText : style.inactiveText);
  }

private:
  const(TabsModel) model;
  TabControlStyle style;
}

/**
 * WidgetView managing registered TabControl root widgets, translating child
 * button mouseDown events to carry the clicked tab index in
 * `AppEvent.view.value[0]`, and synchronizing `WidgetArrayComponent` when any
 * bound `TabsModel` changes.
 */
final class TabControlWidgetView : WidgetViewBase {
  /**
   * Associates a `ModelTracker!TabsModel` with a TabControl root `viewWidget`.
   */
  void bindModel(Widget viewWidget, ref ModelTracker!TabsModel tracker) {
    assert(viewWidget !is null, "viewWidget must not be null");
    if (!isWidgetRegistered(viewWidget)) {
      registerViewWidget(viewWidget);
    }
    widgetModels[viewWidget] = ModelTracker!TabsModel(tracker);
    if (viewWidget.components.widgetArray !is null) {
      viewWidget.components.widgetArray.itemsCount =
        tracker.model.tabNames.length;
      viewWidget.components.widgetArray.modelChanged = true;
    }
  }

  /**
   * Associates a `TabsModel` instance with a TabControl root `viewWidget`.
   */
  void bindModel(Widget viewWidget, TabsModel model) {
    assert(viewWidget !is null, "viewWidget must not be null");
    assert(model !is null, "model must not be null");
    auto tracker = ModelTracker!TabsModel(model);
    bindModel(viewWidget, tracker);
  }

  override void unregisterViewWidget(Widget viewWidget) {
    super.unregisterViewWidget(viewWidget);
    widgetModels.remove(viewWidget);
  }

  /**
   * Translates a child tab button's mouseDown event to the custom event name
   * configured on `viewWidget.components.view.renameEvents` and puts the
   * clicked button's tab index into `sourceEvent.view.value[0]`.
   */
  override void translateEventForViewWidget(
    ref AppEvent sourceEvent,
    Widget viewWidget
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    size_t tabIndex = 0;
    const Widget clickedBtn = sourceEvent.view.widget;
    foreach (i, child; viewWidget.children) {
      if (child is clickedBtn) {
        tabIndex = i;
        break;
      }
    }

    super.translateEventForViewWidget(sourceEvent, viewWidget);
    sourceEvent.view.value[0] = cast(ulong) tabIndex;
  }

  /**
   * Updates `activeTab` in the model bound to `viewWidget`.
   * Returns true if the active tab changed.
   */
  bool selectTab(Widget viewWidget, size_t tabIndex) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto pTracker = viewWidget in widgetModels;
    if (pTracker is null) {
      return false;
    }
    if (tabIndex >= pTracker.model.tabNames.length) {
      return false;
    }
    if (pTracker.model.activeTab == tabIndex) {
      return false;
    }

    auto m = pTracker.edit();
    m.activeTab = tabIndex;
    pTracker.commit(m);
    return true;
  }

  override bool update() {
    bool anyUpdated = false;
    foreach (w; viewWidgets) {
      auto pTracker = w in widgetModels;
      if (pTracker !is null && pTracker.update()) {
        if (w.components.widgetArray !is null) {
          w.components.widgetArray.itemsCount =
            pTracker.model.tabNames.length;
          w.components.widgetArray.modelChanged = true;
          anyUpdated = true;
        }
      }
    }
    return anyUpdated;
  }

private:
  ModelTracker!TabsModel[Widget] widgetModels;
}

/**
 * WidgetViewController reacting to translated TabControl view events, updating
 * the active tab in the bound model without consuming the event (so higher- or
 * lower-level application controllers can also handle the custom event), and
 * driving `TabControlWidgetView.update()`.
 */
final class TabControlWidgetViewController : WidgetViewControllerBase {
  this(UiSystem uiSystem) {
    assert(uiSystem !is null, "uiSystem must not be null");
    super(uiSystem);
  }

  override bool update() {
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.view && ev.view.viewWidget !is null) {
      foreach (v; views) {
        if (v.isWidgetRegistered(ev.view.viewWidget)) {
          if (auto tcv = cast(TabControlWidgetView) v) {
            const size_t tabIdx = cast(size_t) ev.view.value[0];
            tcv.selectTab(ev.view.viewWidget, tabIdx);
          }
          return HandleResult(HandleResult.Result.updateView, false);
        }
      }
    }
    return super.handleEvent(ev);
  }
}

/**
 * Fluent builder constructing a TabControl widget tree and wiring it to
 * `TabControlWidgetView` via `UiRegistry`.
 */
struct TabControlBuilder {
  ref TabControlBuilder model(TabsModel m) return {
    assert(m !is null, "m must not be null");
    tabsTracker = ModelTracker!TabsModel(m);
    hasModel = true;
    return this;
  }

  ref TabControlBuilder model(ref ModelTracker!TabsModel tracker) return {
    tabsTracker = ModelTracker!TabsModel(tracker);
    hasModel = true;
    return this;
  }

  ref TabControlBuilder event(string customEventName) return {
    eventName = customEventName;
    return this;
  }

  ref TabControlBuilder direction(FlexDirection dir) return {
    flexDir = dir;
    return this;
  }

  ref TabControlBuilder gap(float g) return {
    flexGap = g;
    return this;
  }

  ref TabControlBuilder justify(JustifyContent j) return {
    flexJustify = j;
    return this;
  }

  ref TabControlBuilder alignItems(AlignItems a) return {
    flexAlign = a;
    return this;
  }

  ref TabControlBuilder buttonSize(float width, float height) return {
    btnStyle.buttonWidth = width;
    btnStyle.buttonHeight = height;
    return this;
  }

  ref TabControlBuilder style(in TabControlStyle s) return {
    btnStyle = s;
    return this;
  }

  /**
   * Builds the TabControl root Widget.
   *
   * Params:
   *   parent = Parent widget (allowed to be null for root/test widgets).
   *   rect = Initial rectangle of the TabControl container.
   *   registry = UiRegistry used to look up `TabControlWidgetView` (allowed to
   *     be null in isolated tests).
   */
  Widget build(Widget parent, RectF rect, UiRegistry registry = null) {
    if (!hasModel) {
      tabsTracker = ModelTracker!TabsModel(new TabsModel());
      hasModel = true;
    }

    const string targetEvent = eventName.length > 0
      ? eventName
      : defaultTabControlEventName;

    auto provider = new TabButtonsProvider(tabsTracker.model, btnStyle);
    Widget root = WidgetBuilder(parent, rect)
      .flex(flexDir, flexGap, flexJustify, flexAlign)
      .widgetArray(provider, tabsTracker.model.tabNames.length)
      .view(
        registry,
        [tabButtonMouseDownEvent: targetEvent],
        tabControlWidgetViewName
      )
      .build();

    if (registry !is null) {
      if (WidgetView wv = registry.widgetViews.getByName(
            tabControlWidgetViewName
          )) {
        if (auto tcv = cast(TabControlWidgetView) wv) {
          tcv.bindModel(root, tabsTracker);
        }
      }
    }

    return root;
  }

private:
  ModelTracker!TabsModel tabsTracker;
  bool hasModel = false;
  string eventName = defaultTabControlEventName;
  FlexDirection flexDir = FlexDirection.row;
  float flexGap = 10.0f;
  JustifyContent flexJustify = JustifyContent.start;
  AlignItems flexAlign = AlignItems.center;
  TabControlStyle btnStyle;
}

/**
 * Registers a shared `TabControlWidgetView` and
 * `TabControlWidgetViewController` into `ui` and links them together.
 */
TabControlWidgetViewController registerTabControl(UiSystem ui) {
  assert(ui !is null, "ui must not be null");
  auto view = new TabControlWidgetView();
  auto ctrl = new TabControlWidgetViewController(ui);
  ctrl.registerWidgetView(view);
  ui.widgetViews.register(view.getWidgetViewName(), view);
  ui.widgetViewControllers.register(ctrl.getControllerName(), ctrl);
  return ctrl;
}

unittest {
  import yguilib.events.builder : ViewAppEventBuilder;
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
  auto ctrl = registerTabControl(ui);
  assert(ctrl !is null);

  auto registeredView = cast(TabControlWidgetView)
    ui.widgetViews.getByName(tabControlWidgetViewName);
  assert(registeredView !is null);
  assert(
    ui.widgetViewControllers.getByName(tabControlWidgetViewControllerName)
      is ctrl
  );

  auto model = new TabsModel(["Overview", "Audio", "Video"], 0);
  auto tracker = ModelTracker!TabsModel(model);

  TabControlBuilder builder;
  Widget tabRoot = builder
    .model(tracker)
    .event("customTabSwitch")
    .buttonSize(120.0f, 28.0f)
    .gap(8.0f)
    .build(null, RectF(0, 0, 400, 32), ui);

  assert(tabRoot !is null);
  assert(registeredView.isWidgetRegistered(tabRoot));
  assert(tabRoot.components.view !is null);
  assert(tabRoot.components.view.widgetViewName == tabControlWidgetViewName);
  assert(
    tabRoot.components.view.renameEvents[tabButtonMouseDownEvent] ==
      "customTabSwitch"
  );
  assert(tabRoot.components.widgetArray !is null);
  assert(tabRoot.components.widgetArray.itemsCount == 3);

  // Populate child buttons via provider as DataSystem does in preLayout
  auto provider = tabRoot.components.widgetArray.provider;
  foreach (_; 0 .. 3) {
    provider.addWidget(tabRoot);
  }
  foreach (i, child; tabRoot.children) {
    provider.updateWidgetAt(child, i);
  }
  assert(tabRoot.children.length == 3);
  assert(tabRoot.children[0].components.textLabel.caption == "Overview");
  assert(tabRoot.children[0].components.background.color == tabActiveBg);
  assert(tabRoot.children[2].components.textLabel.caption == "Video");
  assert(tabRoot.children[2].components.background.color == tabInactiveBg);

  // Translate mouseDown on button index 2
  AppEvent rawEv = ViewAppEventBuilder(tabButtonMouseDownEvent)
    .widget(tabRoot.children[2])
    .build();
  registeredView.translateEventForViewWidget(rawEv, tabRoot);
  assert(rawEv.view.eventName == "customTabSwitch");
  assert(rawEv.view.viewWidget is tabRoot);
  assert(rawEv.view.value[0] == 2);

  // Controller handles translated event without consuming it, updates model,
  // and requests updateView
  HandleResult hr = ctrl.handleEvent(rawEv);
  assert(hr.result == HandleResult.Result.updateView);
  assert(!hr.consume);
  assert(model.activeTab == 2);

  // View update marks widgetArray.modelChanged
  tabRoot.components.widgetArray.modelChanged = false;
  assert(ctrl.updateView());
  assert(tabRoot.components.widgetArray.modelChanged);

  // Re-apply provider update to verify button highlight switched to index 2
  foreach (i, child; tabRoot.children) {
    provider.updateWidgetAt(child, i);
  }
  assert(tabRoot.children[0].components.background.color == tabInactiveBg);
  assert(tabRoot.children[2].components.background.color == tabActiveBg);
}

version (unittest) {
  void main() {
  }
}
