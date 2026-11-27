# `yguilib` Clibs Bindings Review

```
  date    2026-11-27
  branch  main
  commit  7a96feaa25bba66718bc02d342f18c7c42932731 (fix composite_view after review)
```

Line numbers below refer to that commit.

Scope: `yguilib/source/yguilib/clibs/` (3 D binding modules), cross-checked
against `yguilib/yguilib-clibs/` (`yguilib_sdl3.h`, `yguilib_sdl3_image.h`,
`yguilib_sdl3_ttf.h`).

Paths below are relative to `yguilib/source/yguilib/clibs/`.
Severity: **H** high, **M** medium, **L** low.

```
  Summary
  -------
  correctness, safety & ABI ........ 3 findings (0 H, 1 M, 2 L)
  memory, ownership & NULL safety .. 2 findings (0 H, 2 M, 0 L)
  architecture & API design ........ 1 finding  (0 H, 0 M, 1 L)
  code reuse & duplication ......... 0 findings
  codestyle & maintainability ...... 2 findings (0 H, 0 M, 2 L)
  tests & verification gaps ........ 1 finding  (0 H, 0 M, 1 L)
  -------------------------------------------------------------
  total ............................ 9 findings (0 H, 3 M, 6 L)
```

ABI cross-check: all 60 `extern(C)` functions (32 in `sdl3.d`, 8 in
`sdl3_image.d`, 20 in `sdl3_ttf.d`), 9 structs, 1 union, 4 opaque handles, and
2 C-backed enums match their C headers 1:1 with **zero ABI mismatches**.

---

## Module Coverage

| Module | Lines | Role | Findings (`H/M/L`) |
|---|---:|---|---|
| `sdl3.d` | 747 | `extern(C)` bindings to `yguilib_sdl3` + key/scancode/mod enums | `0H / 2M / 6L` |
| `sdl3_image.d` | 46 | `extern(C)` bindings to `yguilib_sdl3_image` (decode/PNG) | `0H / 2M / 2L` |
| `sdl3_ttf.d` | 101 | `extern(C)` bindings to `yguilib_sdl3_ttf` (fonts/glyphs/layout) | `0H / 3M / 2L` |

---

## 1. Correctness, Safety & ABI Compatibility

### 1.1 [M] Missing `nothrow` and `@nogc` on all `extern(C)` bindings
`sdl3.d:662-725` (`yguilib_sdl3_GLProc` at `:698`), `sdl3_image.d:8-45`,
`sdl3_ttf.d:18-100`

None of the `extern(C)` blocks carry `nothrow` or `@nogc`. C wrappers cannot
throw D exceptions or allocate via the D GC; omitting these attributes prevents
calling any binding from `nothrow`/`@nogc` D code (destructors, `scope(exit)`
cleanup, hot-path rendering/layout).

Fix: Change `extern(C) {` to `extern(C) nothrow @nogc {` in all three files
(verify `GLADloadfunc` compatibility before annotating `yguilib_sdl3_GLProc`).

### 1.2 [L] 64-bit-only union size assertion without per-struct checks
`sdl3.d:110` (vs `yguilib_sdl3.h:102-111`)

`static assert(yguilib_sdl3_Event.sizeof == 40);` only holds on 64-bit targets
(36 bytes on 32-bit). Individual event structs (`sdl3.d:27-97`) lack
`.sizeof`/`.offsetof` assertions.

Fix: Gate the union size check by `(void*).sizeof` and add matching C-side
`_Static_assert`s and D-side `.sizeof` checks for individual structs.

### 1.3 [L] Hardcoded SDL3 `Scancode`/`Keycode`/`Keymod` constants lack C validation
`sdl3.d:124-660`

537 lines (~72% of `sdl3.d`) mirror raw SDL3 enum values without C-side
`_Static_assert` checks against upstream SDL3 headers.

Fix: Add boundary `_Static_assert`s in `yguilib_sdl3.c` or `yguilib_sdl3_test.c`
(or document the pinned SDL3 version).

---

## 2. Memory, Ownership & NULL Safety

### 2.1 [M] Undocumented buffer lifetime on `yguilib_sdl3_ttf_open_font_from_mem`
`sdl3_ttf.d:28-32` (`yguilib_sdl3_ttf.h:45-57`, `yguilib_sdl3_ttf.c:56-60`)

`yguilib_sdl3_ttf_open_font_from_mem` wraps `SDL_IOFromConstMem` +
`TTF_OpenFontIO(io, true, pt_size)`, which borrows `data` without copying; the
caller must keep `data` alive until `yguilib_sdl3_ttf_close_font`. Neither the
C header nor `sdl3_ttf.d` documents this requirement (unlike
`yguilib_sdl3_image.h:28`), risking use-after-free on temporary or GC-movable
buffers.

Fix: Document the lifetime requirement in both `yguilib_sdl3_ttf.h` and
`sdl3_ttf.d`.

### 2.2 [M] Missing NULL & ownership doc comments on D `extern(C)` bindings
`sdl3.d:662-725`, `sdl3_image.d:8-45`, `sdl3_ttf.d:18-100` (and minor gaps in
`yguilib_sdl3.h`, `yguilib_sdl3_ttf.h`)

`codestyle.md` §3 requires documenting nullable pointer parameters and return
values. None of the 60 bound functions in the 3 `.d` files document nullable
inputs (e.g., `rect` in `set_text_input_area`, `w`/`h`/`output` in
`layout_text`, nullable `destroy_*`/`close_*`), nullable returns
(`create_window`, `load_*`, `open_font*`, `render_*`), or returned pointer
lifetimes (`get_error`, `get_surface_pixels`, `TextInputEvent.text`). Also,
`yguilib_sdl3_ttf.h:260` omits `render_glyph` from `destroy_surface`'s comment.

Fix: Add concise NULL/lifetime doc comments in all 3 `.d` binding files and
fill the remaining C header gaps.

---

## 3. Architecture, Encapsulation & API Design

### 3.1 [L] Unused scaffolding `yguilib_sdl3_hello` and unused bindings
`sdl3.d:665, 700, 701, 713-721`

`yguilib_sdl3_hello()` is an undocumented scaffolding leftover with zero
callers. `register_wake_event`, `log`, `get_key_from_scancode`,
`get_scancode_from_name`, and `get_scancode_name` are also unused in D
production code.

Fix: Remove `yguilib_sdl3_hello` and prune unused wrapper entry points to keep
the C wrapper API minimal.

---

## 4. Code Reuse & Duplication

No issues found. Separate `*_get_surface_*`/`destroy_surface` bindings in
`sdl3_image.d` and `sdl3_ttf.d` reflect intentionally distinct opaque handles.

---

## 5. Codestyle & Maintainability

### 5.1 [L] `snake_case` parameter names in `sdl3.d`
`sdl3.d:723-724`

`uint window_id` uses `snake_case` whereas the rest of `sdl3.d` uses
`camelCase` (`timeoutMs`, `keyEvent`, `windowId`).

Fix: Rename `window_id` -> `windowId`.

### 5.2 [L] Inconsistent `extern(C)` on structs and stale module doc names
`sdl3.d:1, 27-108`, `sdl3_image.d:1`, `sdl3_ttf.d:1, 10`

`sdl3_ttf.d:10` annotates `extern(C) struct`, whereas `sdl3.d:27-108` omits
`extern(C)` on its 8 structs and union. Module comments reference
`yguilib-clib-sdl*` instead of the actual Meson targets (`yguilib_sdl3*`).

Fix: Apply `extern(C)` consistently on C-ABI structs/unions and align module
doc comments with the target names.

---

## 6. Tests & Verification Gaps

### 6.1 [L] Weak or missing D-side binding tests
`sdl3.d:727-746`, `sdl3_image.d`, `sdl3_ttf.d`

`sdl3.d`'s unittest checks 9 enum values against their own literals and calls
key-name functions without `yguilib_sdl3_init()`. `sdl3_image.d` and
`sdl3_ttf.d` have no `unittest` blocks.

Fix: Add `.sizeof`/`.offsetof` `static assert`s for all C-ABI structs and
minimal null-safe smoke unittests in `sdl3_image.d` and `sdl3_ttf.d`.

---

## Prioritized Action List

- **Medium**
  1. Mark all `extern(C)` binding blocks `nothrow @nogc`.
  2. Document `yguilib_sdl3_ttf_open_font_from_mem` buffer lifetime and add
     NULL/lifetime doc comments across all 3 `.d` binding files.
- **Low**
  3. Remove `yguilib_sdl3_hello`, add struct layout `static assert`s, and fix
     minor naming/doc nits.
