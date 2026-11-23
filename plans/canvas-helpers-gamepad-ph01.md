# Phase 1: Color String Decoding Helpers (`yguilib`)

Overview: [canvas-helpers-gamepad.md](canvas-helpers-gamepad.md).

## Goal
Add zero-allocation, CTFE-compatible CSS/hex color string decoding helpers
in `yguilib` (`parseColor`, `colorFromString`, `FillStyle.solidFromString`).

## Files & Steps

### 1. `yguilib/source/yguilib/render/render_types.d`
Add `parseColor` and `colorFromString` (using scoped
`import std.typecons : Nullable, nullable;`):

- `Nullable!ColorF parseColor(string s) nothrow @safe @nogc pure`
  - Trim leading and trailing ASCII whitespace (`' '`, `'\t'`, `'\n'`,
    `'\r'`, `'\f'`).
  - Case-insensitive keyword and hex matching:
    - `"transparent"` -> `ColorF(0.0f, 0.0f, 0.0f, 0.0f)`.
    - `#RGB` (3 hex digits): each nibble `h / 15.0f`, `a = 1.0f`.
    - `#RGBA` (4 hex digits): each nibble `h / 15.0f`.
    - `#RRGGBB` (6 hex digits): each byte `b / 255.0f`, `a = 1.0f`.
    - `#RRGGBBAA` (8 hex digits): each byte `b / 255.0f`.
    - Any other `#` length or non-hex char -> `Nullable!ColorF.init`.
  - `rgb(...)` / `rgba(...)` (both accept 3 or 4 components, case-insensitive
    prefix, optional spaces inside parens, no space between `rgb`/`rgba`
    and `(`):
    - Legacy comma syntax: `rgb(r, g, b)` or `rgba(r, g, b, a)` (and
      `rgb(r, g, b, a)` / `rgba(r, g, b)`). RGB channels must all be numbers
      or all percentages; alpha may be a number `[0, 1]` or percentage.
    - Modern space syntax: `rgb(r g b)` or `rgb(r g b / a)` (and `rgba(...)`).
      Each RGB channel may be a number or percentage; optional `/ a` may be
      a number `[0, 1]` or percentage.
    - Reject mixed comma + space/slash syntax (e.g. `rgb(10, 20 30)`,
      `rgb(10, 20, 30 / 0.5)`, `rgb(10 20, 30)`), missing/extra arguments,
      trailing garbage, or non-finite numbers by returning
      `Nullable!ColorF.init`.
    - Clamp RGB numbers to `[0, 255]` (`/ 255.0f`), percentages to
      `[0, 100]` (`/ 100.0f`), and alpha numbers to `[0, 1]`.
  - Implement with small `private` helper functions (each <= ~50 lines,
    under `private:` section label) including a `@nogc @safe pure nothrow`
    ASCII float scanner (do NOT use `std.conv.to`).

- `ColorF colorFromString(string s) nothrow @safe @nogc pure`
  - Calls `parseColor(s)`, `assert(!c.isNull, "invalid color string");`,
    returns `c.isNull ? ColorF(0.0f, 0.0f, 0.0f, 0.0f) : c.get`.

- Add `unittest` blocks covering:
  - `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA` (lower/upper/mixed case,
    surrounding whitespace).
  - `"transparent"`, `"TRANSPARENT"`, `" transparent "`.
  - `rgb(43, 49, 64)`, `rgba(43, 49, 64, 0.5)`, `rgb(50%, 100%, 0%)`,
    `rgba(100%, 0%, 50%, 50%)`, `rgb(43 49 64)`, `rgb(43 49 64 / 0.25)`,
    `rgba(100% 50% 0 / 50%)`, out-of-range clamping (`-10`, `300`, `150%`,
    `-0.5`, `2.0`), scientific notation (`1e2`).
  - CTFE test: `enum ColorF ctfeColor = colorFromString("#2b3140");`.
  - Invalid inputs returning `.isNull`: `""`, `"   "`, `"#12"`, `"#12345"`,
    `"#1234567"`, `"#gggggg"`, `"2b3140"`, `"rgb(1, 2)"`, `"rgb(1, 2, 3, 4, 5)"`,
    `"rgb(1, 2 3)"`, `"rgb(1, 2, 3 / 0.5)"`, `"rgb(100%, 50, 0)"`,
    `"rgb(1, 2, 3) extra"`, `"hsl(0, 100%, 50%)"`.

### 2. `yguilib/source/yguilib/render/canvas/types.d`
- Import `colorFromString` from `yguilib.render.render_types`.
- Add on `FillStyle` (which also works as `StrokeStyle.solidFromString`):
  ```d
  /// Solid color paint decoded from a CSS/hex string (`colorFromString`).
  static FillStyle solidFromString(string s) nothrow @safe @nogc pure {
    return solid(colorFromString(s));
  }
  ```
- Add `unittest` checking `FillStyle.solidFromString("#2b3140")` and
  `StrokeStyle.solidFromString("rgba(75, 85, 107, 0.5)")`.

## Verification
Run and confirm all pass (lines <= 80 chars, codestyle, null-safety):
```bash
ninja -C _build && timeout 300 meson test -C _build
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
```
