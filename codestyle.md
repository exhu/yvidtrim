# Coding Style

## 1. Formatting & Files (D and C)
- Indent with 2 spaces; use LF line endings; max 80 chars per line.
- Put opening `{` on the same line as declarations and control statements.
- Use lowercase-only file names.

## 2. D Naming & Function Signatures
- **Symbol casing:**
  - Modules: `lowercase`
  - Types (classes, structs, interfaces, enums): `PascalCase`
  - Functions, methods, variables, fields, enum values: `camelCase`
  - No consecutive capital letters: use `Id`, `makeGuid`, `colorRgb` (not `ID`,
    `makeGUID`, `colorRGB`).
- **No overloaded functions:** Do not add overloaded functions or methods
  (except for visitor patterns or serialization/conversion). Name each
  function to convey the return value and the arguments it accepts using
  `<returnMeaning>From<ArgMeaning>` (e.g., `pixelsFromLogicPoint`) or
  `<action>With<ArgMeaning>` (e.g., `drawLineWithPoints`,
  `drawLineWithCoords`):
  ```D
  // GOOD
  TimerId startCallbackTimer(
    uint intervalMs, TimerMode mode, TimerCallback cb
  );
  TimerId startControllerTimer(
    Controller target, uint intervalMs, TimerMode mode
  );
  TimerId startSystemTimer(
    WidgetSystem target, uint intervalMs, TimerMode mode
  );
  void drawText(TextParameters text);
  void drawString(string text);
  void drawTextAt(string text, PointF pos);

  // BAD
  TimerId startTimer(uint intervalMs, TimerMode mode, TimerCallback cb);
  TimerId startTimer(Controller target, uint intervalMs = 16);
  void draw(TextParameters text);
  void draw(string text);
  ```
- **No default parameter values:** All parameters must be explicit.
- **Parameter order:** Put the main semantic parameter first (e.g., `text` in
  `drawTextAt`).
- **Many arguments (>5):** Pass a parameter struct as `in` or `ref`, using a
  fluent builder (`with...`):
  ```D
  struct TextParameters {
    string text;
    ColorF color;

    TextParameters* withText(string text) {
      this.text = text;
      return this;
    }

    TextParameters* withColor(ColorF color) {
      this.color = color;
      return this;
    }
  }
  ```
- **Function size:** Split functions longer than ~50 lines or with distinct
  semantic blocks into smaller helpers.

## 3. D Null Safety & Invariants
- Reference types and pointers in parameters and return values are non-null
  by default. If `null` is allowed, document it in the function/method comment.
- Assert non-null arguments in constructors (`assert(arg !is null)`).
- For fields that must never be `null`, add a struct/class `invariant` block
  (`invariant { assert(field !is null); }`) instead of scattering null checks
  or creating silent empty objects. Disable default construction (`@disable
  this();`) when a non-null field requires a constructor argument.

## 4. D Types, Visibility & Constants
- **Const by default:** Prefer `const` for local variables and fields that do
  not change.
- **Visibility section order:** Declare `public` members first, then
  `protected`, then `private`. Use visibility section labels rather than
  per-declaration attributes:
  ```D
  // GOOD
  void myPublicFunction() {}
  private:
  void myPrivateFunction() {}

  // BAD
  public void myPublicFunction() {}
  private void myPrivateFunction() {}
  ```
- **Constructors:** Provide either a single parameterless `this()` or one
  parameterized constructor (`@disable this();` if needed). Keep constructor
  parameters `<= 3` and use them only when fields cannot be initialized
  otherwise (e.g., `const` fields) or for math/geometry value types (`PointF`,
  `RectF`, `ColorF`). Otherwise, initialize fields to sane defaults and set
  them via properties or methods.

## 5. D Modules, Architecture & Assets
- **No umbrella root `package.d`:** Consumers must import subsystems or
  modules explicitly (e.g., `import yguilib.render;`,
  `import yguilib.controls.scrollbars;`).
- **No `public import` re-exports:** Never use `public import` (in
  `package.d` or any other module) to re-export symbols from other modules.
- **Package directories & `package.d`:** Keep a single-module subsystem as a
  single `.d` file rather than `<pkg>/package.d` (unless it encapsulates an
  `internal/` directory). Multi-module packages (e.g., `yguilib.controls`) do
  not require `package.d`; only create `<pkg>/package.d` when `<pkg>` itself
  defines shared top-level types or functions for that subsystem.
- **Internal boundaries:** Place volatile logic, wire formats, OS bindings,
  and concrete drivers in `internal/`. Never mark internal symbols `public`;
  use `package(<root_pkg>)` or file-level `private`.
- **Imports:** Keep file-level imports minimal. Use scoped imports inside
  functions/templates for heavy `std.*` modules unless multiple functions in
  the file share the same import.
- **Assets:** Place small embeddable resources in `assets/<package_name>/`
  (e.g., `assets/yguilib/font.ttf`) and put string imports in `assets.d` or
  `internal/assets.d`.
- **UI controllers vs systems/components:** Use `WidgetComponent` +
  `WidgetSystem` for per-widget or multi-instance behaviors (e.g., focus,
  hover). Use `Controller` for composite multi-widget coordination via named
  events.

## 6. C Coding Style
- **Naming:**
  - Types and enums: `PascalCase`, prefixed with `<lib>_`
  - Defines, enum values, public constants: `UPPER_SNAKE_CASE`, prefixed with
    `<LIB>_`
  - Functions and variables: `snake_case`, public functions prefixed with
    `<lib>_`
  ```c
  typedef struct my_lib_UserProfile {
    const char* user_name;
    const char* address_line;
  } my_lib_UserProfile;

  typedef enum my_lib_WindowStyle {
    MY_LIB_WINDOW_STYLE_NONE,
    MY_LIB_WINDOW_STYLE_RESIZEABLE,
  } my_lib_WindowStyle;
  ```
- **Documentation & NULL:** Document return values and parameters (especially
  plain types like `int`). Always document whether `NULL` is valid for
  accepted/returned pointers (or state `undefined` for third-party libraries).
- **Const:** Prefer `const` for local variables that do not change.
