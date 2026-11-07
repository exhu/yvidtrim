/**
 * tabcontrol_page.d - Page 5 showcase for TabControl, TabControlWidgetView,
 * and TabControlWidgetViewController.
 */
module guidemo.pages.tabcontrol_page;

import guidemo.common : makeSectionCard;
import guidemo.hover_button_system : AnimatedHoverButtonBuilder,
  HoverAnimConfig;
import guidemo.model : DemoModel;
import guidemo.tabcontrol : TabControlBuilder, TabControlStyle, TabsModel;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiRegistry;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.layout_components : AlignItems, FlexDirection,
  JustifyContent;

/// Page 5 widget container showcasing reusable TabControl instances.
final class TabControlPage {
  /// Constructs TabControlPage. `registry` is allowed to be null in headless
  /// tests.
  this(Widget parent, UiRegistry registry = null) {
    assert(parent !is null, "parent must not be null");
    this.registry = registry;
    root = new Widget(parent, RectF(0, 0, 1280, 720));

    subTabsTracker = ModelTracker!TabsModel(
      new TabsModel(["Overview", "Telemetry", "Settings"], 0)
    );
    dynamicTabsTracker = ModelTracker!TabsModel(
      new TabsModel(["Clip 1", "Clip 2", "Clip 3"], 0)
    );
    verticalTabsTracker = ModelTracker!TabsModel(
      new TabsModel(
        ["Video Track", "Audio Track", "Subtitles", "Chapters"],
        0
      )
    );

    buildSwitcherSection();
    buildDynamicSection();
    buildVerticalSection();
    buildArchitectureSection();
  }

  invariant {
    assert(root !is null);
  }

  void update(const DemoModel m) {
    import std.format : format;

    updateSubPanels(m.page5SubTab);

    if (eventLogLabel !is null) {
      eventLogLabel.setCaption(
        format(
          "Last Event: \"%s\" | ViewData.value[0] = %d",
          m.page5LastEventName,
          m.page5LastEventIndex
        )
      );
    }

    if (dynamicStatusLabel !is null) {
      const auto dm = dynamicTabsTracker.model;
      dynamicStatusLabel.setCaption(
        format(
          "Model Tabs: %d / 5 | Active Index: %d (%s)",
          dm.tabNames.length,
          dm.activeTab,
          dm.activeTab < dm.tabNames.length
            ? dm.tabNames[dm.activeTab]
            : "none"
        )
      );
    }

    updateVerticalInspector(m.page5VerticalTab);
  }

  /// Appends a new tab to the dynamic TabsModel (up to 5 tabs).
  size_t addDynamicTab() {
    import std.format : format;

    auto m = dynamicTabsTracker.edit();
    if (m.tabNames.length < 5) {
      const size_t nextNum = m.tabNames.length + 1;
      m.tabNames ~= format("Clip %d", nextNum);
      m.activeTab = m.tabNames.length - 1;
    }
    const size_t count = m.tabNames.length;
    dynamicTabsTracker.commit(m);
    return count;
  }

  /// Removes the last tab from the dynamic TabsModel (down to 1 tab).
  size_t removeDynamicTab() {
    auto m = dynamicTabsTracker.edit();
    if (m.tabNames.length > 1) {
      m.tabNames = m.tabNames[0 .. $ - 1];
      if (m.activeTab >= m.tabNames.length) {
        m.activeTab = m.tabNames.length - 1;
      }
    }
    const size_t count = m.tabNames.length;
    dynamicTabsTracker.commit(m);
    return count;
  }

  /// Resets the dynamic TabsModel back to 3 tabs.
  size_t resetDynamicTabs() {
    auto m = dynamicTabsTracker.edit();
    m.tabNames = ["Clip 1", "Clip 2", "Clip 3"];
    m.activeTab = 0;
    dynamicTabsTracker.commit(m);
    return 3;
  }

  size_t getDynamicActiveTab() {
    return dynamicTabsTracker.model.activeTab;
  }

  Widget getRootWidget() {
    return root;
  }

  void setVisible(bool visible) {
    root.setVisible(visible);
  }

  bool isVisible() const {
    return root.visible;
  }

private:
  void updateSubPanels(size_t activeIdx) {
    const bool p0 = (activeIdx == 0);
    const bool p1 = (activeIdx == 1);
    const bool p2 = (activeIdx >= 2);
    if (subPanel0.visible != p0 ||
        subPanel1.visible != p1 ||
        subPanel2.visible != p2) {
      subPanel0.setVisible(p0);
      subPanel1.setVisible(p1);
      subPanel2.setVisible(p2);
      root.update(WidgetUpdateScope.layout);
    }
  }

  void updateVerticalInspector(size_t trackIdx) {
    import std.format : format;

    static immutable string[4] trackTitles = [
      "Track 0: Video Stream (H.264 / 60 FPS)",
      "Track 1: Stereo Audio (AAC 48 kHz)",
      "Track 2: Subtitle Overlay (UTF-8 ASS)",
      "Track 3: GOP Chapter Markers",
    ];
    static immutable string[4] trackDetails = [
      "Resolution: 1920x1080 | Keyframe interval: 2.0s\n" ~
        "Smart cut re-encodes only boundary GOP segments.",
      "Channels: 2.0 L/R | Bitrate: 192 kbps\n" ~
        "Frame-aligned audio stream copy without re-encoding.",
      "Format: SubStation Alpha | Active cues: 42\n" ~
        "Timestamps shifted automatically to trim in/out points.",
      "Markers: 6 chapters defined\n" ~
        "Click vertical tabs on the left to inspect each track.",
    ];

    const size_t safeIdx = trackIdx < 4 ? trackIdx : 0;
    if (verticalTitleLabel !is null) {
      verticalTitleLabel.setCaption(trackTitles[safeIdx]);
    }
    if (verticalDescLabel !is null) {
      verticalDescLabel.setCaption(trackDetails[safeIdx]);
    }
    if (verticalIndexLabel !is null) {
      verticalIndexLabel.setCaption(
        format("Selected Vertical Tab Index (value[0]): %d", safeIdx)
      );
    }
  }

  void buildSwitcherSection() {
    auto card = makeSectionCard(
      root,
      RectF(20, 68, 605, 280),
      "1. Interactive Sub-Panel Switcher (Event: \"pageTabSwitch\")"
    );

    WidgetBuilder(card, RectF(16, 36, 570, 20))
      .text(
        "Clicking a tab translates mouseDown into \"pageTabSwitch\" with " ~
          "tab index in value[0].",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        12.0f
      )
      .build();

    TabControlBuilder b;
    b.model(subTabsTracker)
      .event("pageTabSwitch")
      .buttonSize(160.0f, 30.0f)
      .gap(10.0f)
      .build(card, RectF(16, 62, 570, 32), registry);

    buildSubPanels(card);

    eventLogLabel = WidgetBuilder(card, RectF(16, 246, 570, 22))
      .text(
        "Last Event: \"none\" | ViewData.value[0] = 0",
        ColorF(0.95f, 0.90f, 0.40f, 1.0f),
        13.0f
      )
      .build();
  }

  void buildSubPanels(Widget card) {
    subPanel0 = makeSubPanelBox(
      card,
      ColorF(0.10f, 0.14f, 0.20f, 1.0f),
      ColorF(0.28f, 0.45f, 0.75f, 1.0f),
      "Overview Panel (Tab Index 0)",
      "TabControl synchronizes its button children from TabsModel.\n" ~
        "TabControlWidgetView translates child button mouseDown events\n" ~
        "and populates AppEvent.view.value[0] with the clicked index."
    );

    subPanel1 = makeSubPanelBox(
      card,
      ColorF(0.10f, 0.18f, 0.16f, 1.0f),
      ColorF(0.25f, 0.65f, 0.50f, 1.0f),
      "Telemetry Panel (Tab Index 1)",
      "Zero heap allocations during event translation:\n" ~
        "- Event name mapped via ViewComponent.renameEvents\n" ~
        "- Tab index stored directly in 64-bit ViewData.value[0] slot."
    );
    subPanel1.setVisible(false);

    subPanel2 = makeSubPanelBox(
      card,
      ColorF(0.18f, 0.13f, 0.20f, 1.0f),
      ColorF(0.60f, 0.38f, 0.78f, 1.0f),
      "Settings Panel (Tab Index 2)",
      "TabControlWidgetViewController updates TabsModel.activeTab\n" ~
        "without consuming the event, allowing DemoController to switch\n" ~
        "these content panels in response to the same event."
    );
    subPanel2.setVisible(false);
  }

  static Widget makeSubPanelBox(
    Widget parent,
    ColorF bgCol,
    ColorF borderCol,
    string title,
    string bodyText
  ) {
    auto box = WidgetBuilder(parent, RectF(16, 104, 573, 130))
      .roundBackground(bgCol, 6.0f)
      .border(borderCol, 1.0f)
      .padding(10, 12)
      .build();

    WidgetBuilder(box, RectF(14, 10, 540, 22))
      .text(title, ColorF(0.95f, 0.98f, 1.0f, 1.0f), 14.0f)
      .build();

    WidgetBuilder(box, RectF(14, 38, 540, 78))
      .text(bodyText, ColorF(0.75f, 0.82f, 0.92f, 1.0f), 12.0f)
      .build();

    return box;
  }

  void buildDynamicSection() {
    auto card = makeSectionCard(
      root,
      RectF(645, 68, 615, 280),
      "2. Dynamic TabsModel & WidgetArray Sync (Event: \"dynamicTabSwitch\")"
    );

    WidgetBuilder(card, RectF(16, 36, 580, 20))
      .text(
        "Mutate TabsModel at runtime: DataSystem pools & reuses tab buttons.",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        12.0f
      )
      .build();

    TabControlBuilder b;
    b.model(dynamicTabsTracker)
      .event("dynamicTabSwitch")
      .buttonSize(108.0f, 30.0f)
      .gap(8.0f)
      .build(card, RectF(16, 62, 580, 32), registry);

    buildDynamicMutationButtons(card);
    buildDynamicInfoBox(card);
  }

  void buildDynamicMutationButtons(Widget card) {
    auto btnRow = WidgetBuilder(card, RectF(16, 108, 580, 42))
      .flex(
        FlexDirection.row,
        12.0f,
        JustifyContent.start,
        AlignItems.center
      )
      .build();

    HoverAnimConfig addCfg;
    addCfg.hoverBg = ColorF(0.18f, 0.55f, 0.35f, 1.0f);
    addCfg.pressBg = ColorF(0.08f, 0.35f, 0.20f, 1.0f);
    addCfg.hoverBorder = ColorF(0.35f, 0.85f, 0.55f, 1.0f);
    addCfg.actionEvent = "page5AddTab";
    makeMutationButton(
      btnRow,
      "+ Add Tab",
      130.0f,
      ColorF(0.12f, 0.24f, 0.18f, 1.0f),
      addCfg
    );

    HoverAnimConfig remCfg;
    remCfg.hoverBg = ColorF(0.65f, 0.20f, 0.25f, 1.0f);
    remCfg.pressBg = ColorF(0.40f, 0.10f, 0.15f, 1.0f);
    remCfg.hoverBorder = ColorF(0.95f, 0.40f, 0.45f, 1.0f);
    remCfg.actionEvent = "page5RemoveTab";
    makeMutationButton(
      btnRow,
      "- Remove Tab",
      140.0f,
      ColorF(0.26f, 0.12f, 0.14f, 1.0f),
      remCfg
    );

    HoverAnimConfig rstCfg;
    rstCfg.hoverBg = ColorF(0.28f, 0.38f, 0.55f, 1.0f);
    rstCfg.pressBg = ColorF(0.12f, 0.18f, 0.30f, 1.0f);
    rstCfg.hoverBorder = ColorF(0.50f, 0.70f, 1.0f, 1.0f);
    rstCfg.actionEvent = "page5ResetTabs";
    makeMutationButton(
      btnRow,
      "Reset (3 Tabs)",
      140.0f,
      ColorF(0.18f, 0.20f, 0.25f, 1.0f),
      rstCfg
    );
  }

  static void makeMutationButton(
    Widget parent,
    string caption,
    float width,
    ColorF bgCol,
    in HoverAnimConfig cfg
  ) {
    AnimatedHoverButtonBuilder b;
    b.text(caption)
      .bg(bgCol)
      .border(cfg.hoverBorder, 1.0f)
      .fixedSize(width, 34.0f)
      .anim(cfg)
      .build(parent, RectF(0, 0, width, 34));
  }

  void buildDynamicInfoBox(Widget card) {
    auto infoBox = WidgetBuilder(card, RectF(16, 162, 583, 102))
      .roundBackground(ColorF(0.09f, 0.11f, 0.14f, 1.0f), 6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f), 1.0f)
      .padding(10, 12)
      .build();

    dynamicStatusLabel = WidgetBuilder(infoBox, RectF(12, 10, 555, 22))
      .text(
        "Model Tabs: 3 / 5 | Active Index: 0 (Clip 1)",
        ColorF(0.45f, 0.90f, 0.65f, 1.0f),
        13.0f
      )
      .build();

    WidgetBuilder(infoBox, RectF(12, 38, 555, 52))
      .text(
        "- Adding a tab increments itemsCount and allocates/shows a button\n" ~
          "- Removing a tab hides excess child widgets without deallocation\n" ~
          "- TabControlWidgetView.update() syncs changes via ModelTracker",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        12.0f
      )
      .build();
  }

  void buildVerticalSection() {
    auto card = makeSectionCard(
      root,
      RectF(20, 360, 605, 284),
      "3. Vertical TabControl & Custom Style (Event: \"verticalTabSwitch\")"
    );

    WidgetBuilder(card, RectF(16, 36, 570, 20))
      .text(
        "FlexDirection.column TabControl with custom emerald active styling.",
        ColorF(0.70f, 0.75f, 0.85f, 1.0f),
        12.0f
      )
      .build();

    TabControlStyle emeraldStyle;
    emeraldStyle.buttonWidth = 155.0f;
    emeraldStyle.buttonHeight = 34.0f;
    emeraldStyle.activeBg = ColorF(0.16f, 0.52f, 0.36f, 1.0f);
    emeraldStyle.activeBorder = ColorF(0.35f, 0.85f, 0.60f, 1.0f);

    TabControlBuilder b;
    b.model(verticalTabsTracker)
      .event("verticalTabSwitch")
      .direction(FlexDirection.column)
      .alignItems(AlignItems.start)
      .gap(8.0f)
      .style(emeraldStyle)
      .build(card, RectF(16, 66, 165, 190), registry);

    buildVerticalInspectorBox(card);
  }

  void buildVerticalInspectorBox(Widget card) {
    auto inspector = WidgetBuilder(card, RectF(192, 66, 396, 196))
      .roundBackground(ColorF(0.09f, 0.12f, 0.15f, 1.0f), 6.0f)
      .border(ColorF(0.22f, 0.32f, 0.40f, 1.0f), 1.0f)
      .padding(12, 14)
      .build();

    verticalTitleLabel = WidgetBuilder(inspector, RectF(14, 14, 368, 24))
      .text(
        "Track 0: Video Stream (H.264 / 60 FPS)",
        ColorF(0.45f, 0.95f, 0.70f, 1.0f),
        14.0f
      )
      .build();

    verticalDescLabel = WidgetBuilder(inspector, RectF(14, 48, 368, 90))
      .text(
        "Resolution: 1920x1080 | Keyframe interval: 2.0s\n" ~
          "Smart cut re-encodes only boundary GOP segments.",
        ColorF(0.78f, 0.84f, 0.92f, 1.0f),
        12.0f
      )
      .build();

    verticalIndexLabel = WidgetBuilder(inspector, RectF(14, 156, 368, 22))
      .text(
        "Selected Vertical Tab Index (value[0]): 0",
        ColorF(0.95f, 0.90f, 0.40f, 1.0f),
        12.0f
      )
      .build();
  }

  void buildArchitectureSection() {
    auto card = makeSectionCard(
      root,
      RectF(645, 360, 615, 284),
      "4. TabControl WidgetView & WidgetViewController Architecture"
    );

    auto archBox = WidgetBuilder(card, RectF(16, 40, 583, 224))
      .roundBackground(ColorF(0.09f, 0.11f, 0.14f, 1.0f), 6.0f)
      .border(ColorF(0.20f, 0.23f, 0.28f, 1.0f), 1.0f)
      .padding(12, 14)
      .build();

    WidgetBuilder(archBox, RectF(14, 12, 555, 22))
      .text(
        "End-to-End Event & Model Synchronization Pipeline:",
        ColorF(0.45f, 0.80f, 1.0f, 1.0f),
        13.0f
      )
      .build();

    WidgetBuilder(archBox, RectF(14, 40, 555, 172))
      .text(
        "1. Registration: TabControlWidgetView & Controller are registered\n" ~
          "   once in UiSystem's UiRegistry at startup.\n" ~
          "2. Construction: TabControlBuilder creates a Flex + WidgetArray\n" ~
          "   root Widget with ViewComponent (\"TabControlWidgetView\")\n" ~
          "   and binds its TabsModel in TabControlWidgetView.\n" ~
          "3. Event Translation: Clicking a tab fires \"tabBtnDown\";\n" ~
          "   translateEventForViewWidget() renames the event and writes\n" ~
          "   the clicked button's child index to ViewData.value[0].\n" ~
          "4. Controller Update: TabControlWidgetViewController updates\n" ~
          "   activeTab in TabsModel and runs TabControlWidgetView.update().",
        ColorF(0.75f, 0.80f, 0.88f, 1.0f),
        12.0f
      )
      .build();
  }

  Widget root;
  UiRegistry registry;

  ModelTracker!TabsModel subTabsTracker;
  ModelTracker!TabsModel dynamicTabsTracker;
  ModelTracker!TabsModel verticalTabsTracker;

  Widget subPanel0;
  Widget subPanel1;
  Widget subPanel2;
  Widget eventLogLabel;
  Widget dynamicStatusLabel;
  Widget verticalTitleLabel;
  Widget verticalDescLabel;
  Widget verticalIndexLabel;
}
