/**
 * tabcontrol.d - Reusable model-driven TabControl widget tree, view, and
 * controller.
 */
module yguilib.controls.tabcontrol;

import yguilib.controller : HandleResult;
import yguilib.controls.common : ButtonFace, WidgetColors, applyEnabledState,
  defaultDisabledColors, findArrowComposite, findWidgetView, firstPositive,
  orDefault, registerWidgetViewPair, styledButton;
import yguilib.controls.composite_view : bindCompositeModel,
  ensureDefaultModelTracker, ensureViewWidgetRegistered, findEntry,
  findOwningView, getEntryField, resolveBuilderRegistry, setBuilderModel,
  setBuilderTracker, unregisterCompositeWidget, updateCompositeEntries;
import yguilib.controls.internal.axis : Axis;
import yguilib.controls.tab_button : TabButtonStyle, createTabButton,
  updateTabButtonState;
import yguilib.events : AppEvent;
import yguilib.model : ModelTracker, VersionedModel;
import yguilib.render.render_types : PointF, RectF;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.data_components : WidgetArrayProvider;
import yguilib.widget.layout_components : AlignItems, FlexDirection, Insets,
  JustifyContent;
import yguilib.widget.scroll_components : ScrollableArea;
import yguilib.widget.widget_view : WidgetViewBase, WidgetViewControllerBase;

/// Internal mouseDown event name emitted by individual tab button children
/// before translation by TabControlWidgetView.
enum tabButtonMouseDownEvent = "tabBtnDown";

/// Internal view event emitted when clicking the left scroll button.
enum tabScrollLeftEvent = "tabScrollLeft";

/// Internal view event emitted when clicking the right scroll button.
enum tabScrollRightEvent = "tabScrollRight";

/// Internal view event emitted by ScrollableArea on scroll/layout changes.
enum tabScrollChangedEvent = "tabScrollChanged";

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

  /// Constructs TabsModel with initial tab captions (`names` allowed to be
  /// null/empty) and active index.
  this(string[] names, size_t initialActiveTab) {
    this.tabNames = names.dup;
    this.activeTab = initialActiveTab;
  }
}

/// Visual styling and sizing configuration for buttons inside a TabControl.
struct TabControlStyle {
  TabButtonStyle button;
  WidgetColors disabled = defaultDisabledColors;
  float arrowButtonSize = 26.0f;
  float arrowGap = 6.0f;
}

/**
 * WidgetArrayProvider creating and updating styled tab buttons synchronized
 * with a TabsModel.
 */
final class TabButtonsProvider : WidgetArrayProvider {
  this(
    UiSystem ui,
    const(TabsModel) model,
    in TabControlStyle style
  ) {
    assert(ui !is null, "ui must not be null");
    assert(model !is null, "model must not be null");
    this.ui = ui;
    this.model = model;
    this.style = style;
  }

  invariant {
    assert(model !is null);
    assert(ui !is null);
  }

  override void addWidget(Widget parent) {
    assert(parent !is null, "parent must not be null");
    createTabButton(
      ui,
      parent,
      null,
      tabButtonMouseDownEvent,
      false,
      style.button,
      "tabButton"
    );
  }

  override void updateWidgetAt(Widget w, size_t index) {
    import std.format : format;

    assert(w !is null, "w must not be null");
    assert(index < model.tabNames.length, "tab index out of bounds");
    assert(w.components.mouseEvent !is null);

    const bool isActive = (index == model.activeTab);
    w.name = format("tabButton_%d", index);
    w.setCaption(model.tabNames[index]);
    w.components.mouseEvent.mouseDown = tabButtonMouseDownEvent;
    updateTabButtonState(w, isActive, style.button);
  }

private:
  UiSystem ui;
  const(TabsModel) model;
  TabControlStyle style;
}

/// Internal bookkeeping entry tracking composite TabControl parts.
final class TabControlEntry {
  ModelTracker!TabsModel tracker;
  Widget leftBtn;
  Widget scrollViewport;
  Widget tabsContainer;
  Widget rightBtn;
  TabControlStyle style;
  FlexDirection direction;
  float lastViewportMain = -1.0f;
  PointF lastContentSize = PointF(0.0f, 0.0f);
  PointF lastViewportSize = PointF(0.0f, 0.0f);
  bool viewDirty = false;

  this(ref ModelTracker!TabsModel tracker) {
    this.tracker = ModelTracker!TabsModel.from(tracker);
  }
}

/**
 * WidgetView managing registered TabControl root widgets, translating child
 * button mouseDown events to carry the clicked tab index in
 * `AppEvent.view.value[0]`, driving scroll navigation buttons, and
 * synchronizing `WidgetArrayComponent` when bound `TabsModel` changes.
 */
final class TabControlWidgetView : WidgetViewBase {
  /**
   * Registers a fully constructed TabControl with its arrow buttons and
   * viewport containers.
   */
  void registerTabControl(
    Widget viewWidget,
    ref ModelTracker!TabsModel tracker,
    Widget leftBtn,
    Widget scrollViewport,
    Widget tabsContainer,
    Widget rightBtn,
    in TabControlStyle style,
    FlexDirection direction
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    ensureViewWidgetRegistered(this, viewWidget);
    auto entry = new TabControlEntry(tracker);
    entry.leftBtn = leftBtn;
    entry.scrollViewport = scrollViewport;
    entry.tabsContainer = tabsContainer;
    entry.rightBtn = rightBtn;
    entry.style = style;
    entry.direction = direction;
    tabEntries[viewWidget] = entry;
    syncTabsCount(entry);
  }

  void registerTabControlWithModel(
    Widget viewWidget,
    TabsModel model,
    Widget leftBtn,
    Widget scrollViewport,
    Widget tabsContainer,
    Widget rightBtn,
    in TabControlStyle style,
    FlexDirection direction
  ) {
    auto tracker = ModelTracker!TabsModel(model);
    registerTabControl(
      viewWidget,
      tracker,
      leftBtn,
      scrollViewport,
      tabsContainer,
      rightBtn,
      style,
      direction
    );
  }

  /**
   * Associates a `ModelTracker!TabsModel` with a TabControl root `viewWidget`.
   */
  void bindModel(Widget viewWidget, ref ModelTracker!TabsModel tracker) {
    assert(viewWidget !is null, "viewWidget must not be null");
    ensureViewWidgetRegistered(this, viewWidget);
    if (auto entry = findEntry(tabEntries, viewWidget)) {
      entry.tracker = ModelTracker!TabsModel.from(tracker);
      syncTabsCount(entry);
      return;
    }

    Widget lBtn, sv, tc, rBtn;
    if (!findArrowComposite(viewWidget, lBtn, sv, tc, rBtn)) {
      lBtn = null;
      sv = null;
      tc = viewWidget;
      rBtn = null;
    }
    registerTabControl(
      viewWidget,
      tracker,
      lBtn,
      sv,
      tc,
      rBtn,
      TabControlStyle(),
      FlexDirection.row
    );
  }

  /**
   * Associates a `TabsModel` instance with a TabControl root `viewWidget`.
   */
  void bindModelWithModel(Widget viewWidget, TabsModel model) {
    bindCompositeModel(this, viewWidget, model);
  }

  override void unregisterViewWidget(Widget viewWidget) {
    unregisterCompositeWidget(this, tabEntries, viewWidget);
  }

  Widget getLeftButton(Widget viewWidget) {
    return getEntryField!"leftBtn"(tabEntries, viewWidget);
  }

  Widget getRightButton(Widget viewWidget) {
    return getEntryField!"rightBtn"(tabEntries, viewWidget);
  }

  Widget getScrollViewport(Widget viewWidget) {
    return getEntryField!"scrollViewport"(tabEntries, viewWidget);
  }

  Widget getTabsContainer(Widget viewWidget) {
    return getEntryField!"tabsContainer"(tabEntries, viewWidget);
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
    const string originalName = sourceEvent.view.eventName;

    if (originalName == tabButtonMouseDownEvent) {
      size_t tabIndex = 0;
      const Widget clickedBtn = sourceEvent.view.widget;
      auto entry = findEntry(tabEntries, viewWidget);
      Widget container = (entry !is null && entry.tabsContainer !is null)
        ? entry.tabsContainer
        : viewWidget;

      foreach (i, child; container.children) {
        if (child is clickedBtn) {
          tabIndex = i;
          break;
        }
      }

      super.translateEventForViewWidget(sourceEvent, viewWidget);
      sourceEvent.view.value[0] = cast(ulong) tabIndex;
      return;
    }

    super.translateEventForViewWidget(sourceEvent, viewWidget);
  }

  /**
   * Updates `activeTab` in the model bound to `viewWidget`.
   * Returns true if the active tab changed.
   */
  bool selectTab(Widget viewWidget, size_t tabIndex) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto entry = findEntry(tabEntries, viewWidget);
    if (entry is null) {
      return false;
    }
    auto tracker = entry.tracker;
    if (tabIndex >= tracker.model.tabNames.length) {
      return false;
    }
    if (tracker.model.activeTab == tabIndex) {
      return false;
    }

    auto m = tracker.edit();
    m.activeTab = tabIndex;
    tracker.commit(m);
    entry.viewDirty = true;
    return true;
  }

  /**
   * Jumps the viewport scroll offset to the next tab button origin,
   * clamped to maxScroll.
   */
  bool scrollNext(Widget viewWidget) {
    return scrollStep(viewWidget, 1);
  }

  /**
   * Jumps the viewport scroll offset to the previous tab button origin,
   * clamped to 0.
   */
  bool scrollPrev(Widget viewWidget) {
    return scrollStep(viewWidget, -1);
  }

  /**
   * Handles layout feedback from ScrollableArea: auto-hides arrow buttons
   * when tabs fit, enables/disables arrows based on scroll bounds, and snaps
   * the scroll offset to the nearest tab left edge on viewport resize.
   */
  bool handleScrollChanged(
    Widget viewWidget,
    in ScrollableArea.AppEventViewValue val
  ) {
    import std.algorithm.comparison : max;

    assert(viewWidget !is null, "viewWidget must not be null");
    auto entry = findEntry(tabEntries, viewWidget);
    if (entry is null || entry.scrollViewport is null ||
        entry.tabsContainer is null) {
      return false;
    }
    const Axis ax = Axis.of(entry.direction);
    const float contentMain = ax.mainCoord(val.contentSize);
    const float viewportMain = ax.mainCoord(val.viewportSize);

    entry.lastContentSize = val.contentSize;
    entry.lastViewportSize = val.viewportSize;

    const float fullAvailable = calcFullAvailableMain(
      viewWidget,
      viewportMain,
      entry,
      ax
    );

    if (contentMain <= fullAvailable + 0.5f) {
      applyFittingScrollState(entry, viewportMain);
      return true;
    }

    setArrowsVisible(entry, true);
    const float maxScroll = max(0.0f, contentMain - viewportMain);
    float currentOffset = ax.mainCoord(val.offset);
    const float otherOffset = ax.crossCoord(val.offset);

    currentOffset = snapOnResize(
      entry,
      ax,
      currentOffset,
      otherOffset,
      viewportMain,
      maxScroll
    );

    entry.lastViewportMain = viewportMain;
    updateArrowButtonStates(entry, currentOffset, maxScroll);
    return true;
  }

  override bool update() {
    return updateCompositeEntries(tabEntries, (TabControlEntry entry) {
      return syncTabsCount(entry);
    });
  }

private:
  enum OriginSearchMode {
    next,
    prev,
    nearest,
  }

  TabControlEntry[Widget] tabEntries;

  bool scrollStep(Widget viewWidget, int dir) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto entry = findEntry(tabEntries, viewWidget);
    if (entry is null || entry.scrollViewport is null ||
        entry.tabsContainer is null) {
      return false;
    }
    auto sa = entry.scrollViewport.components.scrollableArea;
    if (sa is null) {
      return false;
    }

    float currentOffset, contentMain, viewportMain, maxScroll;
    getScrollMetrics(
      entry,
      currentOffset,
      contentMain,
      viewportMain,
      maxScroll
    );
    const bool forward = (dir >= 0);
    if (forward ? (currentOffset >= maxScroll - 0.5f)
                : (currentOffset <= 0.5f)) {
      return false;
    }

    const Axis ax = Axis.of(entry.direction);
    const OriginSearchMode mode = forward
      ? OriginSearchMode.next
      : OriginSearchMode.prev;
    const float targetOrigin = findOrigin(
      entry.tabsContainer,
      ax,
      currentOffset,
      maxScroll,
      mode
    );

    entry.scrollViewport.setScrollOffset(
      ax.withMainCoord(sa.offset, targetOrigin)
    );
    updateArrowButtonStates(entry, targetOrigin, maxScroll);
    entry.viewDirty = true;
    return true;
  }

  static bool syncTabsCount(TabControlEntry entry) {
    assert(entry !is null, "entry must not be null");
    if (
      entry.tabsContainer is null ||
      entry.tabsContainer.components.widgetArray is null
    ) {
      return false;
    }
    entry.tabsContainer.components.widgetArray.itemsCount =
      entry.tracker.model.tabNames.length;
    entry.tabsContainer.components.widgetArray.modelChanged = true;
    return true;
  }

  static float findOrigin(
    Widget tabsContainer,
    Axis axis,
    float currentOffset,
    float maxScroll,
    OriginSearchMode mode
  ) {
    import std.math.algebraic : abs;

    float best = (mode == OriginSearchMode.next) ? maxScroll : 0.0f;
    float minDiff = float.infinity;
    bool found = false;

    foreach (child; tabsContainer.children) {
      if (!child.visible) {
        continue;
      }
      const float orig = axis.mainPos(child.rect);
      final switch (mode) {
      case OriginSearchMode.next:
        if (orig > currentOffset + 0.5f && (!found || orig < best)) {
          best = orig;
          found = true;
        }
        break;
      case OriginSearchMode.prev:
        if (orig < currentOffset - 0.5f && (!found || orig > best)) {
          best = orig;
          found = true;
        }
        break;
      case OriginSearchMode.nearest:
        const float diff = abs(orig - currentOffset);
        if (diff < minDiff) {
          minDiff = diff;
          best = orig;
        }
        break;
      }
    }

    if (best > maxScroll) {
      best = maxScroll;
    }
    if (best < 0.0f) {
      best = 0.0f;
    }
    return best;
  }

  static void applyFittingScrollState(
    TabControlEntry entry,
    float viewportMain
  ) {
    setArrowsVisible(entry, false);
    entry.scrollViewport.setScrollOffset(PointF(0.0f, 0.0f));
    entry.lastViewportMain = viewportMain;
  }

  static void setArrowsVisible(TabControlEntry entry, bool visible) {
    if (entry.leftBtn !is null) {
      entry.leftBtn.setVisible(visible);
    }
    if (entry.rightBtn !is null) {
      entry.rightBtn.setVisible(visible);
    }
  }

  static float snapOnResize(
    TabControlEntry entry,
    Axis ax,
    float currentOffset,
    float otherOffset,
    float viewportMain,
    float maxScroll
  ) {
    import std.math.algebraic : abs;

    const bool isResize = (
      entry.lastViewportMain > 0.0f &&
      abs(viewportMain - entry.lastViewportMain) > 0.5f
    );
    if (!isResize) {
      return currentOffset;
    }

    const float nearestOrigin = findOrigin(
      entry.tabsContainer,
      ax,
      currentOffset,
      maxScroll,
      OriginSearchMode.nearest
    );
    if (abs(nearestOrigin - currentOffset) > 0.5f) {
      currentOffset = nearestOrigin;
      entry.scrollViewport.setScrollOffset(
        ax.makePoint(currentOffset, otherOffset)
      );
    }
    return currentOffset;
  }

  static void getScrollMetrics(
    TabControlEntry entry,
    out float currentOffset,
    out float contentMain,
    out float viewportMain,
    out float maxScroll
  ) {
    import std.algorithm.comparison : max;

    auto sa = entry.scrollViewport.components.scrollableArea;
    const Axis ax = Axis.of(entry.direction);
    currentOffset = (sa !is null) ? ax.mainCoord(sa.offset) : 0.0f;

    contentMain = firstPositive(
      (sa !is null) ? ax.mainCoord(sa.contentSize) : 0.0f,
      ax.mainCoord(entry.lastContentSize),
      (entry.tabsContainer !is null)
        ? ax.mainSize(entry.tabsContainer.rect)
        : 0.0f
    );
    viewportMain = firstPositive(
      (sa !is null) ? ax.mainCoord(sa.viewportSize) : 0.0f,
      ax.mainCoord(entry.lastViewportSize),
      (entry.scrollViewport !is null)
        ? ax.mainSize(entry.scrollViewport.rect)
        : 0.0f
    );
    maxScroll = max(0.0f, contentMain - viewportMain);
  }

  static float calcFullAvailableMain(
    Widget viewWidget,
    float viewportMain,
    TabControlEntry entry,
    Axis ax
  ) {
    const float caMain = ax.mainSize(viewWidget.getContentArea());
    if (caMain > 0.0f) {
      return caMain;
    }
    float full = viewportMain;
    if (entry.leftBtn !is null && entry.leftBtn.visible) {
      full += ax.mainSize(entry.leftBtn.rect) + entry.style.arrowGap;
    }
    if (entry.rightBtn !is null && entry.rightBtn.visible) {
      full += ax.mainSize(entry.rightBtn.rect) + entry.style.arrowGap;
    }
    return full;
  }

  static void updateArrowButtonStates(
    TabControlEntry entry,
    float currentOffset,
    float maxScroll
  ) {
    const bool canScrollLeft = (currentOffset > 0.5f);
    const bool canScrollRight = (currentOffset < maxScroll - 0.5f);
    applyEnabledState(
      entry.leftBtn, canScrollLeft, entry.style.button.inactive,
      entry.style.disabled
    );
    applyEnabledState(
      entry.rightBtn, canScrollRight, entry.style.button.inactive,
      entry.style.disabled
    );
  }
}

/**
 * WidgetViewController reacting to translated TabControl view events, updating
 * active tab and driving scroll actions.
 */
final class TabControlWidgetViewController : WidgetViewControllerBase {
  this(UiSystem uiSystem) {
    assert(uiSystem !is null, "uiSystem must not be null");
    super(uiSystem);
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind != AppEvent.Kind.view || ev.view.viewWidget is null) {
      return super.handleEvent(ev);
    }

    auto tcv = findOwningView!TabControlWidgetView(views, ev.view.viewWidget);
    if (tcv is null) {
      return super.handleEvent(ev);
    }

    const string eventName = ev.view.eventName;
    if (eventName == tabScrollLeftEvent) {
      tcv.scrollPrev(ev.view.viewWidget);
      return HandleResult(HandleResult.Result.updateView, true);
    }
    if (eventName == tabScrollRightEvent) {
      tcv.scrollNext(ev.view.viewWidget);
      return HandleResult(HandleResult.Result.updateView, true);
    }
    if (eventName == tabScrollChangedEvent) {
      auto val = ScrollableArea.AppEventViewValue.fromRaw(ev.view.value);
      tcv.handleScrollChanged(ev.view.viewWidget, val);
      return HandleResult(HandleResult.Result.updateView, true);
    }

    const size_t tabIdx = cast(size_t) ev.view.value[0];
    tcv.selectTab(ev.view.viewWidget, tabIdx);
    return HandleResult(HandleResult.Result.updateView, false);
  }
}

/**
 * Fluent builder constructing a TabControl widget tree and wiring it to
 * `TabControlWidgetView` via `UiRegistry`.
 */
struct TabControlBuilder {
  ref TabControlBuilder name(string controlName) return {
    widgetName = controlName;
    return this;
  }

  ref TabControlBuilder model(TabsModel m) return {
    setBuilderModel(tabsTracker, hasModel, m);
    return this;
  }

  ref TabControlBuilder modelTracker(
    ref ModelTracker!TabsModel tracker
  ) return {
    setBuilderTracker(tabsTracker, hasModel, tracker);
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
    btnStyle.button.width = width;
    btnStyle.button.height = height;
    return this;
  }

  ref TabControlBuilder style(in TabControlStyle s) return {
    btnStyle = s;
    return this;
  }

  /**
   * Builds the TabControl composite Widget tree.
   *
   * Params:
   *   ui = Active UiSystem (must not be null).
   *   parent = Parent widget (allowed to be null for root/test widgets).
   *   rect = Initial rectangle of the TabControl container.
   *   registry = UiRegistry used to look up `TabControlWidgetView` (defaults
   *     to `ui` when null).
   */
  Widget build(
    UiSystem ui,
    Widget parent,
    RectF rect,
    UiRegistry registry
  ) {
    assert(ui !is null, "ui must not be null");
    registry = resolveBuilderRegistry(ui, registry);
    ensureDefaultModelTracker(
      tabsTracker, hasModel, () => new TabsModel(null, 0)
    );

    const string targetEvent = orDefault(
      eventName, defaultTabControlEventName
    );
    const string[string] renameMap = [
      tabButtonMouseDownEvent: targetEvent,
      tabScrollLeftEvent: tabScrollLeftEvent,
      tabScrollRightEvent: tabScrollRightEvent,
      tabScrollChangedEvent: tabScrollChangedEvent,
    ];

    const Axis ax = Axis.of(flexDir);
    const float arrowW = ax.isRow
      ? btnStyle.arrowButtonSize
      : btnStyle.button.width;
    const float arrowH = ax.isRow
      ? btnStyle.button.height
      : btnStyle.arrowButtonSize;
    const string rootName = orDefault(widgetName, "tabControl");

    Widget root = WidgetBuilder.make(ui)
      .parent(parent)
      .name(rootName)
      .rect(rect)
      .flexDirection(flexDir)
      .gap(btnStyle.arrowGap)
      .justify(JustifyContent.start)
      .alignItems(flexAlign)
      .viewEvents(renameMap.dup)
      .viewName(tabControlWidgetViewName)
      .build();

    buildAndRegisterParts(
      ui, registry, root, rootName, rect, ax, arrowW, arrowH
    );
    return root;
  }

private:
  void buildAndRegisterParts(
    UiSystem ui,
    UiRegistry registry,
    Widget root,
    string rootName,
    RectF rect,
    Axis ax,
    float arrowW,
    float arrowH
  ) {
    auto leftBtn = buildArrowButton(
      ui, root, rootName ~ "LeftBtn", arrowW, arrowH,
      ax.decArrow(), tabScrollLeftEvent
    );
    Widget tabsContainer;
    auto scrollViewport = buildViewport(
      ui, root, rootName, rect, ax, tabsContainer
    );
    auto rightBtn = buildArrowButton(
      ui, root, rootName ~ "RightBtn", arrowW, arrowH,
      ax.incArrow(), tabScrollRightEvent
    );

    root.update(WidgetUpdateScope.parentView);
    registerBuiltTabControl(
      registry, root, leftBtn, scrollViewport, tabsContainer, rightBtn
    );
  }

  Widget buildArrowButton(
    UiSystem ui,
    Widget root,
    string name,
    float w,
    float h,
    string label,
    string eventName
  ) {
    ButtonFace face;
    face.colors = btnStyle.disabled;
    face.width = w;
    face.height = h;
    face.cornerRadius = btnStyle.button.cornerRadius;
    face.borderWidth = 1.0f;
    face.fontSize = btnStyle.button.fontSize;
    face.padding = Insets(2, 4, 2, 4);
    return styledButton(ui, root, name, label, face)
      .onMouseDown(eventName)
      .inputEnabled(false)
      .visible(false)
      .build();
  }

  Widget buildViewport(
    UiSystem ui,
    Widget root,
    string rootName,
    RectF rect,
    Axis ax,
    out Widget tabsContainer
  ) {
    const float crossSize = ax.isRow
      ? btnStyle.button.height
      : btnStyle.button.width;
    auto scrollViewport = WidgetBuilder.make(ui)
      .parent(root)
      .name(rootName ~ "Viewport")
      .rect(RectF(0, 0, rect.width, rect.height))
      .sizeComponent(ax.fillMainFixedCross(crossSize))
      .minWidth(1.0f)
      .minHeight(1.0f)
      .scrollableArea()
      .scrollOffset(0.0f, 0.0f)
      .onScrollChanged(tabScrollChangedEvent)
      .clipChildren(true)
      .build();

    auto provider = new TabButtonsProvider(ui, tabsTracker.model, btnStyle);
    tabsContainer = WidgetBuilder.make(ui)
      .parent(scrollViewport)
      .name(rootName ~ "Tabs")
      .rect(RectF(0, 0, 1.0f, 1.0f))
      .autoSize()
      .minWidth(1.0f)
      .minHeight(1.0f)
      .flexDirection(flexDir)
      .gap(flexGap)
      .justify(flexJustify)
      .alignItems(flexAlign)
      .widgetArray(provider)
      .widgetArrayCount(tabsTracker.model.tabNames.length)
      .build();
    return scrollViewport;
  }

  void registerBuiltTabControl(
    UiRegistry registry,
    Widget root,
    Widget leftBtn,
    Widget scrollViewport,
    Widget tabsContainer,
    Widget rightBtn
  ) {
    if (auto tcv = findWidgetView!TabControlWidgetView(
        registry, tabControlWidgetViewName
      )) {
      tcv.registerTabControl(
        root, tabsTracker, leftBtn, scrollViewport,
        tabsContainer, rightBtn, btnStyle, flexDir
      );
    }
  }

  ModelTracker!TabsModel tabsTracker;
  bool hasModel = false;
  string eventName = defaultTabControlEventName;
  FlexDirection flexDir = FlexDirection.row;
  float flexGap = 10.0f;
  JustifyContent flexJustify = JustifyContent.start;
  AlignItems flexAlign = AlignItems.center;
  TabControlStyle btnStyle;
  string widgetName = null;
}

/**
 * Registers a shared `TabControlWidgetView` and
 * `TabControlWidgetViewController` into `ui` and links them together.
 */
TabControlWidgetViewController registerTabControl(UiSystem ui) {
  assert(ui !is null, "ui must not be null");
  return registerWidgetViewPair!(
    TabControlWidgetView,
    TabControlWidgetViewController
  )(ui);
}

unittest {
  import yguilib.controls.tab_button : tabActiveBg, tabInactiveBg;
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
    .modelTracker(tracker)
    .event("customTabSwitch")
    .buttonSize(120.0f, 28.0f)
    .gap(8.0f)
    .build(ui, null, RectF(0, 0, 400, 32), null);

  assert(tabRoot !is null);
  assert(registeredView.isWidgetRegistered(tabRoot));
  assert(tabRoot.components.view !is null);
  assert(tabRoot.components.view.widgetViewName == tabControlWidgetViewName);
  assert(
    tabRoot.components.view.renameEvents[tabButtonMouseDownEvent] ==
      "customTabSwitch"
  );
  assert(
    tabRoot.components.view.renameEvents[tabScrollLeftEvent] ==
      tabScrollLeftEvent
  );
  assert(
    tabRoot.components.view.renameEvents[tabScrollRightEvent] ==
      tabScrollRightEvent
  );
  assert(
    tabRoot.components.view.renameEvents[tabScrollChangedEvent] ==
      tabScrollChangedEvent
  );

  Widget leftBtn = registeredView.getLeftButton(tabRoot);
  Widget scrollViewport = registeredView.getScrollViewport(tabRoot);
  Widget tabsContainer = registeredView.getTabsContainer(tabRoot);
  Widget rightBtn = registeredView.getRightButton(tabRoot);

  assert(leftBtn !is null);
  assert(scrollViewport !is null);
  assert(tabsContainer !is null);
  assert(rightBtn !is null);
  assert(!leftBtn.visible);
  assert(!rightBtn.visible);

  assert(tabsContainer.components.widgetArray !is null);
  assert(tabsContainer.components.widgetArray.itemsCount == 3);

  // Populate child buttons via provider as DataSystem does in preLayout
  auto provider = tabsContainer.components.widgetArray.provider;
  foreach (_; 0 .. 3) {
    provider.addWidget(tabsContainer);
  }
  foreach (i, child; tabsContainer.children) {
    provider.updateWidgetAt(child, i);
  }
  assert(tabsContainer.children.length == 3);
  assert(tabsContainer.children[0].components.textLabel.caption == "Overview");
  assert(tabsContainer.children[0].components.background.color == tabActiveBg);
  assert(tabsContainer.children[2].components.textLabel.caption == "Video");
  assert(
    tabsContainer.children[2].components.background.color == tabInactiveBg
  );

  // Layout positions for child tab buttons:
  // Tab 0: x=0, w=120
  // Tab 1: x=128, w=120
  // Tab 2: x=256, w=120 -> content width = 376
  tabsContainer.children[0].rect = RectF(0, 0, 120, 28);
  tabsContainer.children[1].rect = RectF(128, 0, 120, 28);
  tabsContainer.children[2].rect = RectF(256, 0, 120, 28);

  // 1. Verify fitting state: content 376 <= 400 -> buttons remain hidden
  auto fitVal = ScrollableArea.AppEventViewValue.fromRaw(
    ScrollableArea.AppEventViewValue.pack(
      PointF(376, 28),
      PointF(400, 28),
      PointF(0, 0)
    )
  );
  registeredView.handleScrollChanged(tabRoot, fitVal);
  assert(!leftBtn.visible);
  assert(!rightBtn.visible);

  // 2. Translate mouseDown on child button index 2
  AppEvent rawEv = ViewAppEventBuilder(tabButtonMouseDownEvent)
    .widget(tabsContainer.children[2])
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
  tabsContainer.components.widgetArray.modelChanged = false;
  assert(ctrl.updateView());
  assert(tabsContainer.components.widgetArray.modelChanged);

  // Re-apply provider update to verify button highlight switched to index 2
  foreach (i, child; tabsContainer.children) {
    provider.updateWidgetAt(child, i);
  }
  assert(
    tabsContainer.children[0].components.background.color == tabInactiveBg
  );
  assert(tabsContainer.children[2].components.background.color == tabActiveBg);

  // 3. Overflow state: tabs exceed container (e.g. content 500 > viewport 336)
  auto overflowVal = ScrollableArea.AppEventViewValue.fromRaw(
    ScrollableArea.AppEventViewValue.pack(
      PointF(500, 28),
      PointF(336, 28),
      PointF(0, 0)
    )
  );
  registeredView.handleScrollChanged(tabRoot, overflowVal);
  assert(leftBtn.visible);
  assert(rightBtn.visible);
  assert(!leftBtn.inputEnabled);
  assert(rightBtn.inputEnabled);

  // 4. Scroll right by pressing '>' button
  AppEvent rightEv = ViewAppEventBuilder(tabScrollRightEvent)
    .widget(rightBtn)
    .build();
  registeredView.translateEventForViewWidget(rightEv, tabRoot);
  assert(rightEv.view.eventName == tabScrollRightEvent);
  HandleResult hrRight = ctrl.handleEvent(rightEv);
  assert(hrRight.result == HandleResult.Result.updateView);
  assert(hrRight.consume);

  auto sa = scrollViewport.components.scrollableArea;
  // Next origin > 0 is Tab 1 at x = 128
  assert(sa.offset.x == 128.0f);
  assert(leftBtn.inputEnabled);

  // Scroll right again -> next origin is Tab 2 at x = 256, clamped to maxScroll
  // maxScroll = 500 - 336 = 164. Since 256 > 164, clamped to 164.
  ctrl.handleEvent(rightEv);
  assert(sa.offset.x == 164.0f);
  assert(!rightBtn.inputEnabled);

  // 5. Scroll left by pressing '<' button
  AppEvent leftEv = ViewAppEventBuilder(tabScrollLeftEvent)
    .widget(leftBtn)
    .build();
  registeredView.translateEventForViewWidget(leftEv, tabRoot);
  HandleResult hrLeft = ctrl.handleEvent(leftEv);
  assert(hrLeft.result == HandleResult.Result.updateView);
  assert(hrLeft.consume);

  // Origin strictly less than 164 is Tab 1 at x = 128
  assert(sa.offset.x == 128.0f);
  assert(rightBtn.inputEnabled);

  // Scroll left again -> origin strictly less than 128 is Tab 0 at x = 0
  ctrl.handleEvent(leftEv);
  assert(sa.offset.x == 0.0f);
  assert(!leftBtn.inputEnabled);

  // 6. Viewport resize snap-to-left:
  // Manually set offset to 70 (not aligned with any tab)
  sa.offset = PointF(70.0f, 0.0f);
  // Simulate resize: viewport changes from 336 to 280
  auto resizeVal = ScrollableArea.AppEventViewValue.pack(
    PointF(500, 28),
    PointF(280, 28),
    PointF(70, 0)
  );
  AppEvent changeEv = ViewAppEventBuilder(tabScrollChangedEvent)
    .widget(scrollViewport)
    .valueArray(resizeVal)
    .build();
  registeredView.translateEventForViewWidget(changeEv, tabRoot);
  HandleResult hrChange = ctrl.handleEvent(changeEv);
  assert(hrChange.result == HandleResult.Result.updateView);
  assert(hrChange.consume);

  // Tab 0 is at 0 (dist 70), Tab 1 is at 128 (dist 58). Nearest is 128!
  assert(sa.offset.x == 128.0f);

  // 7. Verify releaseWidget unregisters tabRoot from view and releases tree
  ui.releaseWidget(tabRoot);
  assert(!registeredView.isWidgetRegistered(tabRoot));
  assert(registeredView.getLeftButton(tabRoot) is null);
  assert(tabRoot.released);
  assert(tabsContainer.released);
}
