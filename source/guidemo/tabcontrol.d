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
import yguilib.render.render_types : ColorF, PointF, RectF;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.data_components : WidgetArrayProvider;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.layout_components : AlignItems, Dimension, FlexDirection,
  JustifyContent, Size, SizingMode;
import yguilib.widget.scroll_components : ScrollableArea;
import yguilib.widget.widget_view : WidgetView, WidgetViewBase,
  WidgetViewControllerBase;

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
  this(string[] names = null, size_t initialActiveTab = 0) {
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
  float arrowButtonSize = 26.0f;
  float arrowGap = 6.0f;

  ColorF activeBg = tabActiveBg;
  ColorF activeBorder = tabActiveBorder;
  ColorF activeText = tabActiveText;

  ColorF inactiveBg = tabInactiveBg;
  ColorF inactiveBorder = tabInactiveBorder;
  ColorF inactiveText = tabInactiveText;

  ColorF disabledBg = ColorF(0.11f, 0.12f, 0.15f, 1.0f);
  ColorF disabledBorder = ColorF(0.20f, 0.22f, 0.27f, 1.0f);
  ColorF disabledText = ColorF(0.40f, 0.43f, 0.50f, 1.0f);
}

/**
 * WidgetArrayProvider creating and updating styled tab buttons synchronized
 * with a TabsModel.
 */
final class TabButtonsProvider : WidgetArrayProvider {
  this(
    UiSystem ui,
    const(TabsModel) model,
    in TabControlStyle style = TabControlStyle()
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
    WidgetBuilder(ui.nextWidgetId())
      .parent(parent)
      .name("tabButton")
      .rect(RectF(0, 0, style.buttonWidth, style.buttonHeight))
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
    import std.format : format;

    assert(w !is null, "w must not be null");
    assert(index < model.tabNames.length, "tab index out of bounds");
    assert(w.components.mouseEvent !is null);

    const bool isActive = (index == model.activeTab);
    w.name = format("tabButton_%d", index);
    w.setCaption(model.tabNames[index]);
    w.components.mouseEvent.mouseDown = tabButtonMouseDownEvent;
    w.setBackgroundColor(isActive ? style.activeBg : style.inactiveBg);
    w.setBorderColor(isActive ? style.activeBorder : style.inactiveBorder);
    w.setTextColor(isActive ? style.activeText : style.inactiveText);
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
    in TabControlStyle style = TabControlStyle(),
    FlexDirection direction = FlexDirection.row
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    if (!isWidgetRegistered(viewWidget)) {
      registerViewWidget(viewWidget);
    }
    auto entry = new TabControlEntry(tracker);
    entry.leftBtn = leftBtn;
    entry.scrollViewport = scrollViewport;
    entry.tabsContainer = tabsContainer;
    entry.rightBtn = rightBtn;
    entry.style = style;
    entry.direction = direction;
    tabEntries[viewWidget] = entry;
    if (
      tabsContainer !is null && tabsContainer.components.widgetArray !is null
    ) {
      tabsContainer.components.widgetArray.itemsCount =
        tracker.model.tabNames.length;
      tabsContainer.components.widgetArray.modelChanged = true;
    }
  }

  void registerTabControl(
    Widget viewWidget,
    TabsModel model,
    Widget leftBtn,
    Widget scrollViewport,
    Widget tabsContainer,
    Widget rightBtn,
    in TabControlStyle style = TabControlStyle(),
    FlexDirection direction = FlexDirection.row
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
    if (!isWidgetRegistered(viewWidget)) {
      registerViewWidget(viewWidget);
    }
    auto pEntry = viewWidget in tabEntries;
    if (pEntry is null) {
      Widget lBtn, sv, tc, rBtn;
      if (findTabControlParts(viewWidget, lBtn, sv, tc, rBtn)) {
        registerTabControl(
          viewWidget,
          tracker,
          lBtn,
          sv,
          tc,
          rBtn
        );
      } else {
        registerTabControl(
          viewWidget,
          tracker,
          null,
          null,
          viewWidget,
          null
        );
      }
    } else {
      pEntry.tracker = ModelTracker!TabsModel.from(tracker);
      if (pEntry.tabsContainer !is null &&
          pEntry.tabsContainer.components.widgetArray !is null) {
        pEntry.tabsContainer.components.widgetArray.itemsCount =
          tracker.model.tabNames.length;
        pEntry.tabsContainer.components.widgetArray.modelChanged = true;
      }
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
    tabEntries.remove(viewWidget);
  }

  Widget getLeftButton(Widget viewWidget) {
    if (auto p = viewWidget in tabEntries) {
      return p.leftBtn;
    }
    return null;
  }

  Widget getRightButton(Widget viewWidget) {
    if (auto p = viewWidget in tabEntries) {
      return p.rightBtn;
    }
    return null;
  }

  Widget getScrollViewport(Widget viewWidget) {
    if (auto p = viewWidget in tabEntries) {
      return p.scrollViewport;
    }
    return null;
  }

  Widget getTabsContainer(Widget viewWidget) {
    if (auto p = viewWidget in tabEntries) {
      return p.tabsContainer;
    }
    return null;
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
      auto pEntry = viewWidget in tabEntries;
      Widget container = (pEntry !is null && pEntry.tabsContainer !is null)
        ? pEntry.tabsContainer
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
    auto pEntry = viewWidget in tabEntries;
    if (pEntry is null) {
      return false;
    }
    auto tracker = pEntry.tracker;
    if (tabIndex >= tracker.model.tabNames.length) {
      return false;
    }
    if (tracker.model.activeTab == tabIndex) {
      return false;
    }

    auto m = tracker.edit();
    m.activeTab = tabIndex;
    tracker.commit(m);
    pEntry.viewDirty = true;
    return true;
  }

  /**
   * Jumps the viewport scroll offset to the next tab button origin to the
   * right, clamped to maxScroll.
   */
  bool scrollNext(Widget viewWidget) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto pEntry = viewWidget in tabEntries;
    if (pEntry is null || pEntry.scrollViewport is null ||
        pEntry.tabsContainer is null) {
      return false;
    }
    auto entry = *pEntry;
    if (entry.scrollViewport.components.scrollableArea is null) {
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
    if (currentOffset >= maxScroll - 0.5f) {
      return false;
    }

    const bool isRow = (entry.direction == FlexDirection.row);
    const float nextOrigin = findNextOrigin(
      entry.tabsContainer,
      isRow,
      currentOffset,
      maxScroll
    );

    auto sa = entry.scrollViewport.components.scrollableArea;
    const PointF newOffset = isRow
      ? PointF(nextOrigin, sa.offset.y)
      : PointF(sa.offset.x, nextOrigin);

    entry.scrollViewport.setScrollOffset(newOffset);
    updateArrowButtonStates(entry, nextOrigin, maxScroll);
    entry.viewDirty = true;
    return true;
  }

  /**
   * Jumps the viewport scroll offset to the previous tab button origin to the
   * left, clamped to 0.
   */
  bool scrollPrev(Widget viewWidget) {
    assert(viewWidget !is null, "viewWidget must not be null");
    auto pEntry = viewWidget in tabEntries;
    if (pEntry is null || pEntry.scrollViewport is null ||
        pEntry.tabsContainer is null) {
      return false;
    }
    auto entry = *pEntry;
    if (entry.scrollViewport.components.scrollableArea is null) {
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
    if (currentOffset <= 0.5f) {
      return false;
    }

    const bool isRow = (entry.direction == FlexDirection.row);
    const float prevOrigin = findPrevOrigin(
      entry.tabsContainer,
      isRow,
      currentOffset
    );

    auto sa = entry.scrollViewport.components.scrollableArea;
    const PointF newOffset = isRow
      ? PointF(prevOrigin, sa.offset.y)
      : PointF(sa.offset.x, prevOrigin);

    entry.scrollViewport.setScrollOffset(newOffset);
    updateArrowButtonStates(entry, prevOrigin, maxScroll);
    entry.viewDirty = true;
    return true;
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
    auto pEntry = viewWidget in tabEntries;
    if (pEntry is null || pEntry.scrollViewport is null ||
        pEntry.tabsContainer is null) {
      return false;
    }
    auto entry = *pEntry;
    const bool isRow = (entry.direction == FlexDirection.row);
    const float contentMain = isRow ? val.contentSize.x : val.contentSize.y;
    const float viewportMain = isRow ? val.viewportSize.x : val.viewportSize.y;

    entry.lastContentSize = val.contentSize;
    entry.lastViewportSize = val.viewportSize;

    const float fullAvailable = calcFullAvailableMain(
      viewWidget,
      viewportMain,
      entry,
      isRow
    );

    if (contentMain <= fullAvailable + 0.5f) {
      applyFittingScrollState(entry, viewportMain);
      return true;
    }

    setArrowsVisible(entry, true);
    const float maxScroll = max(0.0f, contentMain - viewportMain);
    float currentOffset = isRow ? val.offset.x : val.offset.y;
    const float otherOffset = isRow ? val.offset.y : val.offset.x;

    currentOffset = snapOnResize(
      entry,
      isRow,
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
    bool anyUpdated = false;
    foreach (w, entry; tabEntries) {
      if (entry.tracker.update()) {
        if (entry.tabsContainer !is null &&
            entry.tabsContainer.components.widgetArray !is null) {
          entry.tabsContainer.components.widgetArray.itemsCount =
            entry.tracker.model.tabNames.length;
          entry.tabsContainer.components.widgetArray.modelChanged = true;
          anyUpdated = true;
        }
      }
      if (entry.viewDirty) {
        entry.viewDirty = false;
        anyUpdated = true;
      }
    }
    return anyUpdated;
  }

private:
  TabControlEntry[Widget] tabEntries;

  static float findNextOrigin(
    Widget tabsContainer,
    bool isRow,
    float currentOffset,
    float maxScroll
  ) {
    float nextOrigin = maxScroll;
    bool found = false;
    foreach (child; tabsContainer.children) {
      if (!child.visible) {
        continue;
      }
      const float orig = isRow ? child.rect.x : child.rect.y;
      if (orig > currentOffset + 0.5f) {
        if (!found || orig < nextOrigin) {
          nextOrigin = orig;
          found = true;
        }
      }
    }
    return (nextOrigin > maxScroll) ? maxScroll : nextOrigin;
  }

  static float findPrevOrigin(
    Widget tabsContainer,
    bool isRow,
    float currentOffset
  ) {
    float prevOrigin = 0.0f;
    bool found = false;
    foreach (child; tabsContainer.children) {
      if (!child.visible) {
        continue;
      }
      const float orig = isRow ? child.rect.x : child.rect.y;
      if (orig < currentOffset - 0.5f) {
        if (!found || orig > prevOrigin) {
          prevOrigin = orig;
          found = true;
        }
      }
    }
    return (prevOrigin < 0.0f) ? 0.0f : prevOrigin;
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
    bool isRow,
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

    const float nearestOrigin = findNearestOrigin(
      entry.tabsContainer,
      isRow,
      currentOffset,
      maxScroll
    );
    if (abs(nearestOrigin - currentOffset) > 0.5f) {
      currentOffset = nearestOrigin;
      const PointF snappedOffset = isRow
        ? PointF(currentOffset, otherOffset)
        : PointF(otherOffset, currentOffset);
      entry.scrollViewport.setScrollOffset(snappedOffset);
    }
    return currentOffset;
  }

  static float findNearestOrigin(
    Widget tabsContainer,
    bool isRow,
    float currentOffset,
    float maxScroll
  ) {
    import std.math.algebraic : abs;

    float nearestOrigin = 0.0f;
    float minDiff = float.infinity;
    foreach (child; tabsContainer.children) {
      if (!child.visible) {
        continue;
      }
      const float orig = isRow ? child.rect.x : child.rect.y;
      const float diff = abs(orig - currentOffset);
      if (diff < minDiff) {
        minDiff = diff;
        nearestOrigin = orig;
      }
    }
    if (nearestOrigin > maxScroll) {
      nearestOrigin = maxScroll;
    }
    if (nearestOrigin < 0.0f) {
      nearestOrigin = 0.0f;
    }
    return nearestOrigin;
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
    const bool isRow = (entry.direction == FlexDirection.row);
    currentOffset = (sa !is null) ? (isRow ? sa.offset.x : sa.offset.y) : 0.0f;

    contentMain = (sa !is null)
      ? (isRow ? sa.contentSize.x : sa.contentSize.y)
      : 0.0f;
    const float lastCMain = isRow
      ? entry.lastContentSize.x
      : entry.lastContentSize.y;
    if (contentMain <= 0.0f && lastCMain > 0.0f) {
      contentMain = lastCMain;
    }
    if (contentMain <= 0.0f && entry.tabsContainer !is null) {
      contentMain = isRow
        ? entry.tabsContainer.rect.width
        : entry.tabsContainer.rect.height;
    }

    viewportMain = (sa !is null)
      ? (isRow ? sa.viewportSize.x : sa.viewportSize.y)
      : 0.0f;
    const float lastVMain = isRow
      ? entry.lastViewportSize.x
      : entry.lastViewportSize.y;
    if (viewportMain <= 0.0f && lastVMain > 0.0f) {
      viewportMain = lastVMain;
    }
    if (viewportMain <= 0.0f && entry.scrollViewport !is null) {
      viewportMain = isRow
        ? entry.scrollViewport.rect.width
        : entry.scrollViewport.rect.height;
    }

    maxScroll = max(0.0f, contentMain - viewportMain);
  }

  static bool findTabControlParts(
    Widget viewWidget,
    out Widget leftBtn,
    out Widget scrollViewport,
    out Widget tabsContainer,
    out Widget rightBtn
  ) {
    if (viewWidget is null || viewWidget.children.length != 3) {
      return false;
    }
    leftBtn = viewWidget.children[0];
    scrollViewport = viewWidget.children[1];
    rightBtn = viewWidget.children[2];
    if (scrollViewport.children.length > 0) {
      tabsContainer = scrollViewport.children[0];
      return true;
    }
    return false;
  }

  static float calcFullAvailableMain(
    Widget viewWidget,
    float viewportMain,
    TabControlEntry entry,
    bool isRow
  ) {
    const RectF ca = viewWidget.getContentArea();
    float full = isRow ? ca.width : ca.height;
    if (full > 0.0f) {
      return full;
    }
    full = viewportMain;
    if (entry.leftBtn !is null && entry.leftBtn.visible) {
      const float btnDim = isRow
        ? entry.leftBtn.rect.width
        : entry.leftBtn.rect.height;
      full += btnDim + entry.style.arrowGap;
    }
    if (entry.rightBtn !is null && entry.rightBtn.visible) {
      const float btnDim = isRow
        ? entry.rightBtn.rect.width
        : entry.rightBtn.rect.height;
      full += btnDim + entry.style.arrowGap;
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

    if (entry.leftBtn !is null) {
      entry.leftBtn.inputEnabled = canScrollLeft;
      entry.leftBtn.setBackgroundColor(
        canScrollLeft ? entry.style.inactiveBg : entry.style.disabledBg
      );
      entry.leftBtn.setBorderColor(
        canScrollLeft ? entry.style.inactiveBorder : entry.style.disabledBorder
      );
      entry.leftBtn.setTextColor(
        canScrollLeft ? entry.style.inactiveText : entry.style.disabledText
      );
    }

    if (entry.rightBtn !is null) {
      entry.rightBtn.inputEnabled = canScrollRight;
      entry.rightBtn.setBackgroundColor(
        canScrollRight ? entry.style.inactiveBg : entry.style.disabledBg
      );
      entry.rightBtn.setBorderColor(
        canScrollRight ? entry.style.inactiveBorder : entry.style.disabledBorder
      );
      entry.rightBtn.setTextColor(
        canScrollRight ? entry.style.inactiveText : entry.style.disabledText
      );
    }
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

  override bool update() {
    return true;
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.view && ev.view.viewWidget !is null) {
      foreach (v; views) {
        if (v.isWidgetRegistered(ev.view.viewWidget)) {
          if (auto tcv = cast(TabControlWidgetView) v) {
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
              auto val =
                ScrollableArea.AppEventViewValue.fromRaw(ev.view.value);
              tcv.handleScrollChanged(ev.view.viewWidget, val);
              return HandleResult(HandleResult.Result.updateView, true);
            }
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
  ref TabControlBuilder name(string controlName) return {
    widgetName = controlName;
    return this;
  }

  ref TabControlBuilder model(TabsModel m) return {
    assert(m !is null, "m must not be null");
    tabsTracker = ModelTracker!TabsModel(m);
    hasModel = true;
    return this;
  }

  ref TabControlBuilder model(ref ModelTracker!TabsModel tracker) return {
    tabsTracker = ModelTracker!TabsModel.from(tracker);
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
   * Builds the TabControl composite Widget tree.
   *
   * Params:
   *   parent = Parent widget (allowed to be null for root/test widgets).
   *   rect = Initial rectangle of the TabControl container.
   *   registry = UiRegistry used to look up `TabControlWidgetView` (allowed to
   *     be null in isolated tests).
   */
  Widget build(
    UiSystem ui,
    Widget parent,
    RectF rect,
    UiRegistry registry = null
  ) {
    if (registry is null) {
      registry = ui;
    }
    if (!hasModel) {
      tabsTracker = ModelTracker!TabsModel(new TabsModel());
      hasModel = true;
    }

    const string targetEvent = eventName.length > 0
      ? eventName
      : defaultTabControlEventName;

    string[string] renameMap;
    renameMap[tabButtonMouseDownEvent] = targetEvent;
    renameMap[tabScrollLeftEvent] = tabScrollLeftEvent;
    renameMap[tabScrollRightEvent] = tabScrollRightEvent;
    renameMap[tabScrollChangedEvent] = tabScrollChangedEvent;

    const bool isRow = (flexDir == FlexDirection.row);
    const float arrowW = isRow
      ? btnStyle.arrowButtonSize
      : btnStyle.buttonWidth;
    const float arrowH = isRow
      ? btnStyle.buttonHeight
      : btnStyle.arrowButtonSize;

    const string rootName = (widgetName.length > 0)
      ? widgetName
      : "tabControl";

    Widget root = WidgetBuilder(ui.nextWidgetId())
      .parent(parent)
      .name(rootName)
      .rect(rect)
      .flex(flexDir, btnStyle.arrowGap, JustifyContent.start, flexAlign)
      .view(registry, renameMap, tabControlWidgetViewName)
      .build();

    auto leftBtn = WidgetBuilder(ui.nextWidgetId())
      .parent(root)
      .name(rootName ~ "LeftBtn")
      .rect(RectF(0, 0, arrowW, arrowH))
      .fixedSize(arrowW, arrowH)
      .padding(2, 4, 2, 4)
      .roundBackground(btnStyle.disabledBg, btnStyle.cornerRadius)
      .border(btnStyle.disabledBorder, 1.0f)
      .text(
        isRow ? "<" : "^",
        btnStyle.disabledText,
        btnStyle.fontSize,
        TextLabel.Alignment.center
      )
      .onMouseDown(tabScrollLeftEvent)
      .build();
    leftBtn.inputEnabled = false;
    leftBtn.visible = false;

    auto scrollViewport = WidgetBuilder(ui.nextWidgetId())
      .parent(root)
      .name(rootName ~ "Viewport")
      .rect(RectF(0, 0, rect.width, rect.height))
      .size(
        isRow
          ? Size.fraction(1.0f, 0.0f)
          : Size.fraction(0.0f, 1.0f)
      )
      .minSize(1.0f, 1.0f)
      .scrollableArea(PointF(0.0f, 0.0f), tabScrollChangedEvent)
      .clipChildren(true)
      .build();
    if (isRow) {
      scrollViewport.components.size.height =
        Dimension(btnStyle.buttonHeight, SizingMode.fixed);
    } else {
      scrollViewport.components.size.width =
        Dimension(btnStyle.buttonWidth, SizingMode.fixed);
    }

    auto provider = new TabButtonsProvider(ui, tabsTracker.model, btnStyle);
    auto tabsContainer = WidgetBuilder(ui.nextWidgetId())
      .parent(scrollViewport)
      .name(rootName ~ "Tabs")
      .rect(RectF(0, 0, 1.0f, 1.0f))
      .autoSize()
      .minSize(1.0f, 1.0f)
      .flex(flexDir, flexGap, flexJustify, flexAlign)
      .widgetArray(provider, tabsTracker.model.tabNames.length)
      .build();

    auto rightBtn = WidgetBuilder(ui.nextWidgetId())
      .parent(root)
      .name(rootName ~ "RightBtn")
      .rect(RectF(0, 0, arrowW, arrowH))
      .fixedSize(arrowW, arrowH)
      .padding(2, 4, 2, 4)
      .roundBackground(btnStyle.disabledBg, btnStyle.cornerRadius)
      .border(btnStyle.disabledBorder, 1.0f)
      .text(
        isRow ? ">" : "v",
        btnStyle.disabledText,
        btnStyle.fontSize,
        TextLabel.Alignment.center
      )
      .onMouseDown(tabScrollRightEvent)
      .build();
    rightBtn.inputEnabled = false;
    rightBtn.visible = false;

    root.update(WidgetUpdateScope.parentView);

    if (registry !is null) {
      if (WidgetView wv = registry.widgetViews.getByName(
            tabControlWidgetViewName
          )) {
        if (auto tcv = cast(TabControlWidgetView) wv) {
          tcv.registerTabControl(
            root,
            tabsTracker,
            leftBtn,
            scrollViewport,
            tabsContainer,
            rightBtn,
            btnStyle,
            flexDir
          );
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
  string widgetName = null;
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
    .build(ui, null, RectF(0, 0, 400, 32));

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
    .value(resizeVal)
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

version (unittest) {
  void main() {
  }
}
