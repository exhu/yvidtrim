# Review: `yguilib/source/yguilib/controls`

Scope: the five modules in `yguilib/source/yguilib/controls/`. The review
looks for duplicated logic and code that could move into shared modules.

| Module                   | Lines | Pattern                                  |
|--------------------------|------:|------------------------------------------|
| `hover_button_system.d`  |   937 | WidgetSystem + WidgetComponent (ECS)     |
| `scrollbars.d`           |  1442 | Model + WidgetView + Controller + Builder|
| `tab_button.d`           |   186 | Free factory functions + color constants |
| `tabcontrol.d`           |  1337 | Model + WidgetView + Controller + Builder|
| `virtlist.d`             |  1430 | Model + WidgetView + Controller + Builder|

`scrollbars`, `tabcontrol` and `virtlist` all use the same "composite
control" design:

```
  XxxModel : VersionedModel
  XxxStyle (struct)
  XxxEntry (class)        tracker + part widgets + direction + viewDirty
  XxxWidgetView           Entry[Widget] map, getters, bindModel, update()
  XxxWidgetViewController handleEvent -> find view -> dispatch by name
  XxxBuilder (struct)     name/model/modelTracker/event/direction/style,
                          build root -> buildAndRegisterParts ->
                          registerBuiltXxx (lookup view by name, cast)
  registerXxx(ui)         new view + new ctrl + register both
```

Most of the duplication comes from this design: each module writes the
same pattern out again by hand. The sections below list the duplication
first and then propose the new modules.

---

## 1. Duplication across modules

### 1.1 `registerXxx(UiSystem)`: same code in 3 modules

`registerScrollbars` (scrollbars.d:1139), `registerTabControl`
(tabcontrol.d:1118) and `registerVirtList` (virtlist.d:1077) contain the
same code. Only the types differ:

```d
auto view = new V();
auto ctrl = new C(ui);
ctrl.registerWidgetView(view);
ui.widgetViews.register(view.getWidgetViewName(), view);
ui.widgetViewControllers.register(ctrl.getControllerName(), ctrl);
return ctrl;
```

**Extract:** `C registerWidgetViewPair(V, C)(UiSystem ui)`. Keep the three
public functions as one-line wrappers so that call sites in `guidemo` stay
the same.

### 1.2 Entry map and part getters in every WidgetView

Each view keeps an `Entry[Widget]` map and repeats these snippets:

- **Ensure registered.** `if (!isWidgetRegistered(w)) registerViewWidget(w);`
  appears 6 times (scrollbars 188, 208; tabcontrol 188, 236; virtlist 208,
  232).
- **Lookup-or-bail.**
  `auto pEntry = w in entries; if (pEntry is null) return false;
  auto entry = *pEntry;` appears about 20 times.
- **Part getters.** Getters that return a field or `null` appear 5 times in
  scrollbars, 4 times in tabcontrol and 4 times in virtlist.
- **`bindModelWithModel`.** All 3 copies are identical: assert, wrap in
  `ModelTracker`, call `bindModel`.
- **`unregisterViewWidget`.** All 3 call `super` and remove the entry.
  `virtlist` also clears `scrollbarToRoot`, and it calls `super` in a
  different order from the other two.
- **`update()` loop.** All 3 copies are identical:
  `if (entry.tracker.update()) { <sync> }` followed by
  `if (entry.viewDirty) { entry.viewDirty = false; anyUpdated = true; }`.
  Only the `<sync>` part differs: `syncEntryVisuals`, the widgetArray count
  sync, or `syncModelToViewport`.

**Extract:** a generic base class `CompositeWidgetView!(Entry, M)` (see
section 3.2). Each module then implements only `onModelChanged(entry)`,
`bindFromTree(...)` and the module-specific operations.

### 1.3 Pass-through `translateEventForViewWidget` overrides

The overrides in `ScrollbarWidgetView` (scrollbars.d:272) and
`VirtListWidgetView` (virtlist.d:313) only assert and call `super`. They
can be deleted.

### 1.4 Controller boilerplate

All three controllers repeat the following:

- A constructor that asserts `uiSystem` and calls `super`.
- `override bool update() { return true; }`.
- The loop `foreach (v; views) { if (!v.isWidgetRegistered(...)) continue;
  auto x = cast(XView) v; ... }`.
- An `emitPositionChanged` method (scrollbars.d:832) and an
  `emitVisibleChanged` method (virtlist.d:674). Both look up the event name
  and then build
  `ViewAppEventBuilder(name).widget(w).viewWidget(w).value(v)` before
  calling `uiSystem.sendAppEvent`. Apart from their names, the two are the
  same.

**Extract:**

- `V findOwningView(V)(WidgetView[] views, Widget viewWidget)`.
- `void emitViewValueEvent(UiSystem ui, string eventName, Widget w,
  ulong value)`, which skips empty names.
- Optionally, an abstract `CompositeWidgetViewController!V` base class that
  provides the constructor, `update()` and an
  `abstract HandleResult handleOwnEvent(V view, AppEvent ev)` hook.

`tabcontrol`'s `handleEvent` is nested 5 levels deep (tabcontrol.d:821).
It would become flat under this base class.

### 1.5 Builder boilerplate

`ScrollbarBuilder`, `TabControlBuilder` and `VirtListBuilder` repeat
identical code:

- Setters `name`, `model`, `modelTracker`, `event`, `direction` and `style`.
- Fields `widgetName`, `hasModel`, `xxxTracker` and `eventName`.
- `if (registry is null) registry = ui;`.
- `if (!hasModel) { tracker = ModelTracker!M(new M(...)); ... }`.
- `rootName = widgetName.length > 0 ? widgetName : "default"`.
- `registerBuiltXxx`: `registry.widgetViews.getByName(name)`, followed by
  `cast(XView)` and a call to `registerXxx(...)`.

The `x.length > 0 ? x : default` idiom appears about 10 times across all 5
modules. That includes the `eventName` defaults inside the views and the
names in `createTabButton` and `AnimatedHoverButtonBuilder`.

**Extract:**

- `string orDefault(string value, string fallback)`.
- `V findWidgetView(V)(UiRegistry registry, string name)`, which returns
  `null` when the registry or the view is missing.
- `mixin template CompositeBuilderCommon(Self, M, alias defaultEvent)`,
  which generates the shared setters and fields plus a `resolveModel(...)`
  helper.

Small inconsistencies that these helpers would also fix:

- `TabControlBuilder.build` has no `assert(ui !is null)`.
- `renameMap.dup` is used in scrollbars and virtlist but not in tabcontrol.

### 1.6 Styled "label button" construction (5 copies)

These five places use nearly the same `WidgetBuilder` chain:

```
.parent .name .rect(0,0,w,h) .fixedSize(w,h) [.padding]
.roundBg(bg) .bgRadius(r) .border(border) .borderWidth(1)
.text(label) .textColor(text) .fontSize(fs)
.textAlign(center) .onMouseDown(event)
```

- `tab_button.createTabButton` (tab_button.d:62)
- `TabButtonsProvider.addWidget` (tabcontrol.d:107). This is an almost
  exact copy of `createTabButton`.
- `TabControlBuilder.buildArrowButton` (tabcontrol.d:1013)
- `ScrollbarBuilder.buildArrowBtn` (scrollbars.d:998)
- `AnimatedHoverButtonBuilder.applyVisualStyle` (hover_button_system.d:222)
  uses the same chain and adds conditional radius/border handling.

**Extract:** a `ButtonFace` struct (colors, radius, font size, padding,
border width) and
`WidgetBuilder styledButton(UiSystem ui, Widget parent, string name,
float w, float h, string label, in ButtonFace face, string mouseDownEvent)`.
The function returns the builder so that callers can chain more calls such
as `.inputEnabled(false).visible(false)`. `TabButtonsProvider.addWidget`
should then call `createTabButton`, or both should call `styledButton`.

### 1.7 Applying color triplets and enabled/disabled state (7+ copies)

The sequence `setBackgroundColor / setBorderColor / setTextColor`, chosen
by a boolean, appears in these places:

- `tab_button.updateTabButtonState` (tab_button.d:87)
- `TabButtonsProvider.updateWidgetAt` (tabcontrol.d:136). This copies
  `updateTabButtonState` with style colors instead of constants.
- `ScrollbarWidgetView.updateArrowStates`, once for dec and once for inc
  (scrollbars.d:690)
- `TabControlWidgetView.updateArrowButtonStates`, once for left and once for
  right (tabcontrol.d:771)
- `ScrollbarWidgetView.updateThumbColors` (bg/border only,
  scrollbars.d:673)
- `AnimatedHoverButtonSystem.cleanInvisibleButtons` / `applyVisualState`
  (bg/border only)

The arrow-state functions also set `inputEnabled` together with the colors.

**Extract:**

```d
struct WidgetColors { ColorF bg; ColorF border; ColorF text; }
void applyColors(Widget w, in WidgetColors c);          // null-safe
void applyEnabledState(Widget w, bool enabled,
                       in WidgetColors on, in WidgetColors off);
```

Then regroup the style structs around `WidgetColors`:

- `ScrollbarStyle`: `arrow`, `thumb`, `thumbDrag`, `disabled`.
- `TabControlStyle`: `active`, `inactive`, `disabled`.
- `tab_button`: `tabActive`, `tabInactive`.

`ScrollbarStyle.disabled*` and `TabControlStyle.disabled*` have almost the
same values (they differ by 0.02 to 0.04). Defining a single
`defaultDisabledColors` constant would unify them.

### 1.8 Axis (`isRow ? x : y`) arithmetic

There are about 40 axis-selection ternaries across `scrollbars`,
`tabcontrol` and `virtlist`:

- **Main component of a value.** `isRow ? p.x : p.y` for `PointF`, and
  `isRow ? r.width : r.height` for `RectF` and `Widget.rect`.
- **Rebuilding an offset.** `isRow ? PointF(m, o.y) : PointF(o.x, m)` appears
  3 times in tabcontrol.
- **Fill-main size.** `isRow ? Size.fraction(1,0) : Size.fraction(0,1)`
  appears in scrollbars.d:1040 and tabcontrol.d:1046.
- **Fixed cross size.** The fixed-cross-size block appears in tabcontrol.d:1055
  and in virtlist `buildVertical/HorizontalScrollbar`.
- **Arrow geometry.** Arrow sizes are computed with `isRow ? a : b` pairs,
  and arrow labels with `isRow ? "<" : "^"` / `isRow ? ">" : "v"`. Both
  appear in scrollbars and tabcontrol.

**Extract:** a small value type:

```d
struct Axis {
  bool isRow;
  static Axis of(FlexDirection d);
  float main(PointF p) const;   float cross(PointF p) const;
  float main(RectF r) const;    float cross(RectF r) const;
  PointF make(float main, float cross) const;
  PointF withMain(PointF p, float main) const;
  Size fillMain() const;
  string decArrow() const;      string incArrow() const;
}
```

### 1.9 `findXxxParts` tree probing

`ScrollbarWidgetView.findScrollbarParts` (scrollbars.d:726) and
`TabControlWidgetView.findTabControlParts` (tabcontrol.d:724) use the same
"3 children, the middle one has child[0]" layout probe:

```
root
 |- [0] dec / left button
 |- [1] track / viewport
 |     `- [0] thumb / tabsContainer
 `- [2] inc / right button
```

**Extract:**
`bool findArrowComposite(Widget root, out Widget dec, out Widget middle,
out Widget inner, out Widget inc)`.

### 1.10 Test helpers duplicated

- `verifyAllNamed` appears in scrollbars.d:1197 (nested) and in
  virtlist.d:1164.
- `calcAbsRect` appears in virtlist.d:1154. Every pipeline-driven control
  test needs it.
- `DummyHost : WidgetSystemHost` appears in hover_button_system.d:708, and
  other WidgetSystem tests are likely to need it.
- `RecordingUiSystem` appears in scrollbars.d:1153. This kind of UI system
  records sent events, which most controller tests want.

**Extract:** a `version (unittest)` module, for example
`yguilib.controls.testing` or the existing widget test fixture area. Check
the `WidgetFixture` conventions first.

---

## 2. Duplication within a single module

### scrollbars.d

- The pair `effMin = m.min; effMax = max(m.min, m.max); range = ...` is
  computed 6 times. Move it into `ScrollbarModel`:
  `long effMax() const`, `long range() const`, `long clampValue(long) const`.
- `stepDecrement` and `stepIncrement` are identical except for the sign.
  Replace them with `stepBy(viewWidget, int dir, out long newValue)` and
  keep the two names as thin wrappers.
- `updateThumbDrag` and `syncEntryVisuals` both compute
  `trackLen -> thumbLen -> maxTravel`. Extract
  `ThumbMetrics computeThumbMetrics(entry)`.
- `std.algorithm.comparison : max/clamp` is imported locally about 15 times,
  sometimes twice inside one function (lines 337, 405, 539, 545). Import it
  once at module level.
- `computeDraggedOffset` is public but only used internally. Make it
  private.

### tabcontrol.d

- `scrollNext` and `scrollPrev` (lines 383 to 470) are about 90% identical.
  Merge them into `scrollStep(viewWidget, int dir)`.
- `findNextOrigin`, `findPrevOrigin` and `findNearestOrigin` all iterate
  over visible children and read `isRow ? rect.x : rect.y`. A shared
  `visibleChildOrigins(container, axis)` range would serve all three, or a
  single `findOrigin(container, axis, offset, Mode mode)` could replace them.
- The widgetArray count sync
  (`itemsCount = tabNames.length; modelChanged = true`) appears 3 times:
  `registerTabControl`, `bindModel` and `update`. Extract
  `syncTabsCount(entry)`.
- `getScrollMetrics` applies the fallback chain "component -> cached ->
  rect" twice. Extract `firstPositive(a, b, c)`.
- `bindModel` calls `registerTabControl` in two branches that differ only in
  their part arguments.

### virtlist.d

- `applyMainScrollOffset` and `applyCrossScrollOffset` are identical except
  for the component method they call.
- `handleRootEvent` and `handleOwnedScrollbarEvent` repeat the main/cross
  dispatch. Extract `routeScrollEvent(vlv, root, evName, value)`.
- `buildVerticalScrollbar` and `buildHorizontalScrollbar` differ only by
  axis. Merge them into `buildScrollbar(..., FlexDirection dir, ...)` using
  `Axis` (section 1.8).
- `createMainScrollTracker` and `createCrossScrollTracker` differ only in
  the step. Replace both with `makeScrollTracker(long step)`.
- Several magic numbers are duplicated:
  - The cross step `24.0f` (lines 349, 1031).
  - The default item size `48.0f` (lines 148, 444).
  - The effective item size computation (lines 891, 1014).

  Name them as constants and give the builder an `effItemSize()` helper.
- `syncScrollbarTracker` changes a `ScrollbarModel` in place. Consider
  moving it into `scrollbars.d` as
  `ScrollbarModel.setMetrics(min, max, visible, step, value)` returning
  `bool changed`. Any control that has scrollbars could then reuse it.

### hover_button_system.d

- `lerpColor` (line 649) is a general color helper. Move it next to
  `ColorF` in `yguilib.render.render_types`, either as `ColorF.lerp` or as a
  free `lerpColor`.
- `isWidgetVisible` (line 511, checks the ancestor chain) is a general
  widget query. It belongs in the `yguilib.widget` utilities.
- `findHitButton` (line 660) is a general "topmost visible widget with
  component `C` under point, respecting clip" query. Turn it into
  `findTopmostWithComponent!C(VisibleWidgets, PointF)` in
  `yguilib.widget.visible`.
- `updateCursorNorm` builds the normalized point inside a rect by hand.
  Add `PointF normalizedIn(RectF r, PointF p)` as a geometry helper.
- The "unhover/unpress + track" block appears 3 times:
  `handleMouseMotion`, `handleWindowMouseLeave` and `cleanInvisibleButtons`.
  Add `comp.releaseInteraction()` and `comp.resetToNormal(w)` methods.
- `stepComponent` evaluates the gradient-busy condition twice
  (lines 567 and 583). Compute it once.

### tab_button.d

- `createTabButton` takes 8 positional parameters, while `TabControlStyle`
  already groups the same data. Introduce `TabButtonStyle`, built from
  `WidgetColors` and the existing default constants, and use it in both
  places:
  - `createTabButton(ui, parent, label, event, isActive, style, name)`
  - `updateTabButtonState(btn, isActive, style)`

  `TabControlStyle` can then embed `TabButtonStyle` rather than duplicating
  its fields.

---

## 3. Proposed new modules

```
yguilib/source/yguilib/
  controls/
    common.d          (new) shared helpers for all controls
    composite_view.d  (new) generic Entry-map view + controller bases
    internal/
      axis.d          (new) Axis value type (package-internal)
    testing.d         (new, version(unittest)) test fixtures
    hover_button_system.d, scrollbars.d, tab_button.d,
    tabcontrol.d, virtlist.d   (slimmed)
  render/render_types.d   + lerpColor / ColorF.lerp
  widget/visible.d        + findTopmostWithComponent!C
  widget/...              + isEffectivelyVisible(Widget)
```

### 3.1 `yguilib.controls.common`

| Symbol                                   | Replaces                        |
|------------------------------------------|---------------------------------|
| `struct WidgetColors`                    | loose bg/border/text fields     |
| `applyColors(Widget, in WidgetColors)`   | 7+ triplet setter blocks        |
| `applyEnabledState(w, on, offColors...)` | arrow/thumb enable logic        |
| `defaultDisabledColors`                  | two near-identical palettes     |
| `struct ButtonFace` + `styledButton(..)` | 5 WidgetBuilder button chains   |
| `orDefault(string, string)`              | ~10 `len > 0 ? a : b` ternaries |
| `registerWidgetViewPair!(V, C)(ui)`      | 3 `registerXxx` bodies          |
| `findWidgetView!V(registry, name)`       | 3 `registerBuiltXxx` lookups    |
| `emitViewValueEvent(ui, name, w, value)` | `emitPositionChanged` etc.      |
| `findArrowComposite(root, out ...)`      | 2 `findXxxParts` probes         |

### 3.2 `yguilib.controls.composite_view`

```d
abstract class CompositeWidgetView(Entry, M) : WidgetViewBase {
  // Entry must expose: ModelTracker!M tracker; bool viewDirty;
  protected Entry[Widget] entries;

  protected void ensureRegistered(Widget w);
  protected Entry entryFor(Widget w);            // null if missing
  protected Entry[Widget] allEntries();
  Widget part(string field)(Widget viewWidget);  // getter generator
  void bindModelWithModel(Widget w, M model);    // shared impl

  override void unregisterViewWidget(Widget w);  // calls onUnregister hook
  override bool update();                        // tracker/viewDirty loop

  protected abstract bool onModelChanged(Entry e);
  protected void onUnregister(Widget w, Entry e) {}
}

abstract class CompositeWidgetViewController(V) : WidgetViewControllerBase {
  this(UiSystem ui);
  override bool update() { return true; }
  override HandleResult handleEvent(AppEvent ev); // finds owning V
  protected abstract HandleResult handleOwnEvent(V view, AppEvent ev);
}
```

`mixin template CompositeBuilderCommon(Self, M, alias defaultEvent)` could
also live here, since it belongs with the same pattern.

### 3.3 `yguilib.controls.internal.axis`

This module holds the `Axis` struct from section 1.8. It is
package-internal because only control implementations need it. If layout
code turns out to need the same helpers, it can move to
`yguilib.widget.layout_components` later.

### 3.4 `yguilib.controls.testing` (unittest only)

This module holds `verifyAllNamed`, `calcAbsRect`, `RecordingUiSystem` and
`DummyWidgetSystemHost`.

---

## 4. Estimated impact

| Area                             | Approx. lines removed |
|----------------------------------|----------------------:|
| register functions               |                   ~20 |
| view entry/getter/update boiler. |                  ~150 |
| controller boilerplate + emit    |                   ~60 |
| builder setters + registration   |                  ~120 |
| button chains + color triplets   |                  ~110 |
| axis ternaries / merged twins    |                  ~140 |
| test helpers                     |                   ~40 |
| **Total (net of new modules)**   |       **~450 to 550** |

These figures are rough. The bigger gain is that the next composite control
(for example a combobox or a slider) would only need its model, its entry
and its own interaction logic.

---

## 5. Suggested order (low risk first)

1. **Pure helpers, no behavior change.** `lerpColor` into `render_types`,
   `orDefault`, `WidgetColors` and `applyColors`, `Axis`, module-level
   imports, and the `ScrollbarModel` range helpers.
2. **Merge the in-module twins.** `stepBy`, `scrollStep`, `buildScrollbar`,
   `makeScrollTracker`, `routeScrollEvent` and `syncTabsCount`.
3. **Share the button face.** `ButtonFace` and `styledButton`, and make
   `TabButtonsProvider` reuse `createTabButton`.
4. **Cross-module helpers.** `registerWidgetViewPair`, `findWidgetView` and
   `emitViewValueEvent`. Delete the pass-through
   `translateEventForViewWidget` overrides.
5. **Bases and mixin.** Introduce `CompositeWidgetView` and
   `CompositeWidgetViewController`, then the builder mixin.
6. **Test fixtures.** Move the test helpers into `controls/testing.d`.

Every step must pass `ninja -C _build && meson test -C _build`. Each new
module needs a Meson test target, and `ARCHITECTURE.md` should be updated
for the new `controls/common`, `composite_view` and `internal/axis`
modules.

## 6. Open questions

- **Module layout.** Should `common.d` and `composite_view.d` stay separate
  (recommended), or should everything go into one `controls/common.d`?
- **Visibility.** Should `Axis` be package-internal (recommended for now),
  or public in `widget/layout_components`?
- **Template bases.** Is a templated base class acceptable for the views,
  or would you prefer free-function helpers that keep each view's class
  hierarchy flat? The free functions are less invasive, but they remove
  less code.
