# Phase 2: `controls/common.d`, `composite_view.d`, `testing.d`, `tab_button.d`

## Objective

Create the three new `yguilib.controls` modules (`common.d`,
`composite_view.d` using free functions with no templated classes, and
`testing.d` under `version (unittest):`), refactor `tab_button.d` to use
`WidgetColors` and `styledButton`, and wire them into `yguilib/meson.build`.

## Reference Files

- `yguilib/source/yguilib/controls/tab_button.d`
- `yguilib/source/yguilib/controls/scrollbars.d`
- `yguilib/source/yguilib/controls/tabcontrol.d`
- `yguilib/source/yguilib/controls/virtlist.d`
- `yguilib/source/yguilib/controls/hover_button_system.d`
- `yguilib/meson.build`

## Detailed Steps

### 1. Create `yguilib/source/yguilib/controls/common.d`

Declare `module yguilib.controls.common;` with public helpers:

- **Color & enabled state helpers:**
  - `struct WidgetColors { ColorF bg; ColorF border; ColorF text; }`
  - `enum defaultDisabledColors`:
    ```d
    enum defaultDisabledColors = WidgetColors(
      ColorF(0.11f, 0.12f, 0.15f, 1.0f),
      ColorF(0.19f, 0.21f, 0.25f, 1.0f),
      ColorF(0.39f, 0.42f, 0.48f, 1.0f)
    );
    ```
  - `void applyColors(Widget w, in WidgetColors c)`: null-safe, calls
    `w.setBackgroundColor(c.bg)`, `w.setBorderColor(c.border)`,
    `w.setTextColor(c.text)`.
  - `void applyBgAndBorderColors(Widget w, ColorF bg, ColorF border)`:
    null-safe, calls `w.setBackgroundColor(bg)` and
    `w.setBorderColor(border)`.
  - `void applyEnabledState`:
    `void applyEnabledState(Widget w, bool enabled, in WidgetColors on,
    in WidgetColors off)` — null-safe, sets `w.inputEnabled = enabled` and
    calls `applyColors(w, enabled ? on : off)`.

- **Button face & builder helpers:**
  - `struct ButtonFace`:
    - `WidgetColors colors;`
    - `float width = 0.0f;`
    - `float height = 0.0f;`
    - `float cornerRadius = 4.0f;`
    - `float borderWidth = 1.0f;`
    - `float fontSize = 13.0f;`
    - `Insets padding;`
  - `applyButtonFaceStyle`:
    `void applyButtonFaceStyle(ref WidgetBuilder b, string label,
    in ButtonFace face)` — applies `roundBg` / `bg`, `border` / `borderStyle` /
    `borderRadius` (when `borderWidth > 0.0f`), `text(label)`,
    `textColor(face.colors.text)`, `fontSize(face.fontSize)`,
    `textAlign(TextLabel.Alignment.center)`.
  - `styledButton`:
    ```d
    WidgetBuilder styledButton(
      UiSystem ui,
      Widget parent,
      string name,
      string label,
      in ButtonFace face
    )
    ```
    (5 parameters per `codestyle.md`; `parent` may be null) configures
    `parent`, `name`, `rect(RectF(0, 0, face.width, face.height))`,
    `fixedSize(face.width, face.height)`, `padding(face.padding)` (when
    non-zero), and `applyButtonFaceStyle(b, label, face)`, returning `b` for
    further chaining (`.onMouseDown(...)`, `.inputEnabled(...)`, etc.).

- **General utilities, registry & view event helpers:**
  - `string orDefault(string value, string fallback) nothrow @safe @nogc`
  - `float firstPositive(float a, float b, float c) nothrow @safe @nogc`
  - `C registerWidgetViewPair(V, C)(UiSystem ui)`: asserts `ui !is null`,
    creates `V` and `C(ui)`, links `ctrl.registerWidgetView(view)`, registers
    both in `ui.widgetViews` and `ui.widgetViewControllers`, returns `ctrl`.
  - `V findWidgetView(V)(UiRegistry registry, string name)`: returns `null` if
    `registry is null`, else `cast(V) registry.widgetViews.getByName(name)`.
  - `emitViewValueEvent`:
    `void emitViewValueEvent(UiSystem ui, string eventName, Widget viewWidget,
    ulong value)` — asserts `ui !is null` and `viewWidget !is null`; skips when
    `eventName.length == 0`; otherwise sends
    `ViewAppEventBuilder(eventName).widget(viewWidget).viewWidget(viewWidget)`
    with `.value(value).build()`.
  - `findArrowComposite`:
    ```d
    bool findArrowComposite(
      Widget root,
      out Widget dec,
      out Widget middle,
      out Widget inner,
      out Widget inc
    )
    ```
    probes 3-child `[dec, middle, inc]` where `middle.children.length > 0`
    and sets `inner = middle.children[0]`.

- Add thorough `unittest` blocks for all functions above.

### 2. Create `yguilib/source/yguilib/controls/composite_view.d`

Declare `module yguilib.controls.composite_view;` using **free functions** (and
no templated classes):

- `void ensureViewWidgetRegistered(WidgetView view, Widget viewWidget)`:
  asserts `view !is null && viewWidget !is null`; calls
  `view.registerViewWidget(viewWidget)` when
  `!view.isWidgetRegistered(viewWidget)`.
- `Entry findEntry(Entry)(Entry[Widget] entries, Widget viewWidget)`:
  returns `(viewWidget !is null)` lookup `*p`, else `null`.
- `getEntryField`:
  `auto getEntryField(string field, Entry)(Entry[Widget] entries,
  Widget viewWidget)` — if `auto e = findEntry(entries, viewWidget)` returns
  `__traits(getMember, e, field)`, else
  `typeof(__traits(getMember, Entry.init, field)).init`.
- `void bindCompositeModel(V, M)(V view, Widget viewWidget, M model)`:
  asserts `view !is null`, `viewWidget !is null`, `model !is null`; creates
  `auto tracker = ModelTracker!M(model);` and calls
  `view.bindModel(viewWidget, tracker)`.
- `unregisterCompositeWidget`:
  ```d
  void unregisterCompositeWidget(Entry)(
    WidgetViewBase view,
    ref Entry[Widget] entries,
    Widget viewWidget
  )
  ```
  asserts `view !is null`; removes `viewWidget` from `entries` and calls
  `view.WidgetViewBase.unregisterViewWidget(viewWidget)` (verify with `ldc2`
  that calling the non-virtual base method avoids infinite recursion).
- `updateCompositeEntries`:
  ```d
  bool updateCompositeEntries(Entry)(
    Entry[Widget] entries,
    scope bool delegate(Entry) onModelChanged
  )
  ```
  asserts `onModelChanged !is null`; loops `foreach (w, entry; entries)`,
  runs `entry.tracker.update()` -> `onModelChanged(entry)` and checks
  `entry.viewDirty`.
- `V findOwningView(V)(WidgetView[] views, Widget viewWidget)`:
  returns `null` if `viewWidget is null`; iterates `views`, checks
  `v.isWidgetRegistered(viewWidget)` and `cast(V) v`.
- Builder free functions:
  - `UiRegistry resolveBuilderRegistry(UiSystem ui, UiRegistry registry)`:
    asserts `ui !is null`; returns `(registry !is null) ? registry : ui`.
  - `setBuilderModel`:
    `void setBuilderModel(M)(ref ModelTracker!M tracker, ref bool hasModel,
    M model)` — asserts `model !is null`; sets
    `tracker = ModelTracker!M(model); hasModel = true;`.
  - `setBuilderTracker`:
    `void setBuilderTracker(M)(ref ModelTracker!M tracker, ref bool hasModel,
    ref ModelTracker!M src)` — sets
    `tracker = ModelTracker!M.from(src); hasModel = true;`.
  - `ensureDefaultModelTracker`:
    ```d
    void ensureDefaultModelTracker(M)(
      ref ModelTracker!M tracker,
      ref bool hasModel,
      scope M delegate() makeDefault
    )
    ```
    if `!hasModel`, asserts `makeDefault !is null`, creates default model and
    sets `tracker = ModelTracker!M(makeDefault()); hasModel = true;`.

- Add thorough `unittest` blocks for all free functions.

### 3. Create `yguilib/source/yguilib/controls/testing.d`

Declare `module yguilib.controls.testing;` wrapped in `version (unittest):`:
- `void verifyAllNamed(const Widget w)`
- `RectF calcAbsRect(const Widget w)`
- `final class RecordingUiSystem : UiSystemImpl` (records `sentEvents`)
- `class DummyWidgetSystemHost : WidgetSystemHost` (records `sentEvents`,
  `activeTimers`, dummy registries)
- Add `unittest` verifying each helper.

### 4. Refactor `yguilib/source/yguilib/controls/tab_button.d`

- Define `tabActiveColors` and `tabInactiveColors` (`WidgetColors`) from the
  existing color enums.
- Define `struct TabButtonStyle`:
  - `float width = defaultTabButtonWidth;`
  - `float height = defaultTabButtonHeight;`
  - `float cornerRadius = defaultTabButtonRadius;`
  - `float fontSize = defaultTabButtonFontSize;`
  - `Insets padding = Insets(5, 8, 5, 8);`
  - `WidgetColors active = tabActiveColors;`
  - `WidgetColors inactive = tabInactiveColors;`
- Update `createTabButton` and `updateTabButtonState` to take
  `in TabButtonStyle style` and delegate to `styledButton`, `orDefault`, and
  `applyColors`. Check all callers of `createTabButton` and
  `updateTabButtonState` across the repo first so every call site and test is
  updated cleanly.

### 5. Register New Modules in `yguilib/meson.build`

Add in alphabetical order under `yguilib/controls/`:
- `'source/yguilib/controls/common.d',`
- `'source/yguilib/controls/composite_view.d',`
- `'source/yguilib/controls/testing.d',`

## Verification

Run:
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
```
All commands must pass with 0 errors.
