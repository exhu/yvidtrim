# Refactor `yguilib.controls`

Overview for refactoring the five modules in
`yguilib/source/yguilib/controls/` based on
`documentation/controls-review.md` and design constraints:

- Keep `yguilib.controls.common` and `yguilib.controls.composite_view` separate.
- Keep `Axis` package-internal in `yguilib.controls.internal.axis`
  (`package(yguilib):`).
- **No templated classes**: keep `ScrollbarWidgetView`,
  `TabControlWidgetView`, and `VirtListWidgetView` flat subclasses of
  `WidgetViewBase`, and keep their controllers flat subclasses of
  `WidgetViewControllerBase`. Implement shared view, controller, entry-map,
  and builder operations as **free functions** in
  `yguilib.controls.composite_view`.
- Extract shared test fixtures into `yguilib.controls.testing`
  (`version (unittest):`).

## Architecture Overview

```
+----------------------------------------------------------------------------+
| Foundation Helpers                                                         |
|  +-- render/render_types.d  : lerpColor, normalizedIn                      |
|  +-- widget/package.d       : isEffectivelyVisible                         |
|  +-- widget/visible.d       : findTopmostWithComponent!C                   |
|  +-- widget/widget_view.d   : WidgetViewControllerBase.update() default    |
|  +-- controls/internal/axis.d (package(yguilib)) : struct Axis             |
+------------------------------------+---------------------------------------+
                                     ^
                                     | used by
+------------------------------------+---------------------------------------+
| Shared Controls Modules                                                    |
|  +-- controls/common.d                                                     |
|  |     WidgetColors, defaultDisabledColors, applyColors,                   |
|  |     applyBgAndBorderColors, applyEnabledState, ButtonFace,              |
|  |     applyButtonFaceStyle, styledButton, orDefault, firstPositive,       |
|  |     registerWidgetViewPair, findWidgetView, emitViewValueEvent,         |
|  |     findArrowComposite                                                  |
|  +-- controls/composite_view.d (free functions, no templated classes)      |
|  |     ensureViewWidgetRegistered, findEntry, getEntryField,               |
|  |     bindCompositeModel, unregisterCompositeWidget,                      |
|  |     updateCompositeEntries, findOwningView, resolveBuilderRegistry,     |
|  |     setBuilderModel, setBuilderTracker, ensureDefaultModelTracker       |
|  +-- controls/testing.d (version (unittest))                               |
|        verifyAllNamed, calcAbsRect, RecordingUiSystem,                     |
|        DummyWidgetSystemHost                                               |
+------------------------------------+---------------------------------------+
                                     ^
                                     | imported by
+------------------------------------+---------------------------------------+
| Refactored Controls & Demo Pages                                           |
|  +-- controls/tab_button.d          (TabButtonStyle + styledButton)        |
|  +-- controls/hover_button_system.d (helpers + ButtonFace + testing)       |
|  +-- controls/scrollbars.d          (+ guidemo/pages/scrollbars_page.d)    |
|  +-- controls/tabcontrol.d          (+ guidemo/pages/tabcontrol_page.d)    |
|  +-- controls/virtlist.d            (+ ARCHITECTURE.md & TODO.md)          |
+----------------------------------------------------------------------------+
```

## Design Rules

- Adhere strictly to `codestyle.md`: 2-space indent, <= 80 chars/line, opening
  `{` on same line, no overloaded regular methods, no default parameter values,
  section visibility labels (`public` then `protected:` then `private:`),
  scoped imports for heavy `std.*` modules, non-null assertions and invariants.
- Every new module is registered in `yguilib/meson.build` so `yguilib_test`
  runs all its `unittest` blocks.

## Phases

- Phase 1: [controls-refactor-ph01.md](controls-refactor-ph01.md)
  - Core helpers in `render_types.d`, `widget/package.d`, `widget/visible.d`,
    `widget_view.d`, and new `controls/internal/axis.d`.
- Phase 2: [controls-refactor-ph02.md](controls-refactor-ph02.md)
  - New `controls/common.d`, `controls/composite_view.d`, `controls/testing.d`,
    and refactor `controls/tab_button.d`.
- Phase 3: [controls-refactor-ph03.md](controls-refactor-ph03.md)
  - Refactor `controls/hover_button_system.d`, `controls/scrollbars.d`, and
    `source/guidemo/pages/scrollbars_page.d`.
- Phase 4: [controls-refactor-ph04.md](controls-refactor-ph04.md)
  - Refactor `controls/tabcontrol.d`, `source/guidemo/pages/tabcontrol_page.d`,
    `controls/virtlist.d`, and update `ARCHITECTURE.md` / `TODO.md`.
