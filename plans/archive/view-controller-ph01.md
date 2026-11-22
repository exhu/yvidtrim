# Phase 1: Model, View, and Test Runner

Extract `MainModel` and `MainView` from `source/yvidtrim/app.d` into dedicated
modules and add `source/yvidtrim/test_main.d` for unified unit testing.

## Rules & Conventions
- Adhere to `codestyle.md`: 2-space indent, LF, max 80 chars/line, opening `{`
  on same line, visibility sections (`public:`, `private:`), no default args,
  no consecutive caps, non-null assertions in constructors, `invariant` blocks.
- Do not modify `source/yvidtrim/app.d`, `meson.build`, `ARCHITECTURE.md`, or
  `TODO.md` in Phase 1 (those belong to Phase 2).

## Tasks

### 1. Create `source/yvidtrim/model.d`
Create `yvidtrim.model` containing `MainModel`:
```d
module yvidtrim.model;

import yguilib.model : VersionedModel;
import yguilib.widget.layout_components : AlignItems;

final class MainModel : VersionedModel {
  bool toggleVisible = true;
  float alphaValue = 0.3f;
  bool qPressed;
  bool aPressed;
  AlignItems alignItems;
}
```

### 2. Create `source/yvidtrim/view.d`
Extract `MainView` from `source/yvidtrim/app.d` into `yvidtrim.view`:
- `@disable this();`
- `this(UiSystem ui, ref ModelTracker!MainModel otherTracker)` asserting
  `ui !is null` and `fc !is null`.
- `invariant` asserting `ui !is null`, `fc !is null`, `widgets.root !is null`,
  `widgets.toggle !is null`, `widgets.alpha !is null`, and
  `widgets.container !is null`.
- `void update()` synchronizing `toggleVisible`, `alphaValue`, and
  `alignItems` via `tracker.update()`.
- `Widget rootWidget()` as a `public` method (in the `public:` section).
- Add a headless `unittest` block using `yguilib.internal.uisystem_impl :
  UiSystemImpl` (`new UiSystemImpl(null)`) that:
  - Constructs `ModelTracker!MainModel(new MainModel())` and `MainView`.
  - Verifies `view.rootWidget() !is null` and all widgets in the tree have
    non-empty names.
  - Edits and commits `MainModel` (`toggleVisible = false`, `alphaValue = 0.7f`,
    `alignItems = AlignItems.center`), calls `view.update()`, and asserts that
    the widgets reflect the updated model state.

### 3. Create `source/yvidtrim/test_main.d`
Create the shared unit test runner stub matching `source/guidemo/test_main.d`:
```d
module yvidtrim.test_main;

version (unittest) {
  void main() {
  }
}
```

## Verification (Phase 1)
Run style and null-safety checks on the newly created files:
```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
  source/yvidtrim/model.d source/yvidtrim/view.d source/yvidtrim/test_main.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d \
  source/yvidtrim/model.d source/yvidtrim/view.d source/yvidtrim/test_main.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d \
  source/yvidtrim/model.d source/yvidtrim/view.d source/yvidtrim/test_main.d
```
