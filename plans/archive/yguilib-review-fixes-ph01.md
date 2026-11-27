# ph01: `clibs` Bindings & C Wrappers (`clibs` 1.1-6.1)

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-clibs.md` (commit `7a96feaa`).
Paths below are relative to `yguilib/`.

Goal: Address all 9 findings in `yguilib/source/yguilib/clibs/` and matching
C wrapper headers/sources/tests in `yguilib/yguilib-clibs/`.

## Files

- `source/yguilib/clibs/sdl3.d`, `sdl3_image.d`, `sdl3_ttf.d`
- `yguilib-clibs/yguilib_sdl3.h`, `yguilib_sdl3.c`, `yguilib_sdl3_test.c`
- `yguilib-clibs/yguilib_sdl3_ttf.h`

## Steps

1. **`nothrow @nogc` bindings (`1.1`)**:
   - Change `extern(C) {` to `extern(C) nothrow @nogc {` in `sdl3.d`,
     `sdl3_image.d`, and `sdl3_ttf.d`.
   - **Pitfall**: `subprojects/glad2gles31d/source/glad2/gles2.d` declares
     `GLADapiproc = void function()` and `GLADloadfunc` without
     `nothrow @nogc`. Keep `alias yguilib_sdl3_GLProc = extern(C) void
     function();` compatible with `gladLoadGLES2(&yguilib_sdl3_gl_get_proc_address)`
     in `window.d`.
2. **ABI layout & enum assertions (`1.2`, `1.3`)**:
   - In `sdl3.d`, gate `yguilib_sdl3_Event.sizeof` by `(void*).sizeof`
     (40 on 64-bit, 36 on 32-bit).
   - Add per-struct `.sizeof`/`.offsetof` `static assert`s in `sdl3.d` and
     matching `_Static_assert`s (plus boundary SDL3 `Scancode`/`Keycode`/
     `Keymod` `_Static_assert`s) in `yguilib_sdl3_test.c`.
3. **NULL, lifetime & doc comments (`2.1`, `2.2`)**:
   - Document `yguilib_sdl3_ttf_open_font_from_mem` borrowed `data` lifetime
     (must stay alive until `yguilib_sdl3_ttf_close_font`) in both
     `yguilib_sdl3_ttf.h` and `sdl3_ttf.d`.
   - Add concise NULL/ownership/lifetime doc comments on all 60 bound
     functions in `sdl3.d`, `sdl3_image.d`, and `sdl3_ttf.d`.
   - Update `yguilib_sdl3_ttf.h` `destroy_surface` comment to mention
     `yguilib_sdl3_ttf_render_glyph`.
4. **Remove unused scaffolding & bindings (`3.1`)**:
   - Use `rdmd .agents/skills/search-code/scripts/search_code.d` to verify
     zero D callers for `yguilib_sdl3_hello`,
     `yguilib_sdl3_register_wake_event`, `yguilib_sdl3_log`,
     `yguilib_sdl3_get_key_from_scancode`,
     `yguilib_sdl3_get_scancode_from_name`, `yguilib_sdl3_get_scancode_name`.
   - Remove unused entry points from `sdl3.d`, `yguilib_sdl3.h`,
     `yguilib_sdl3.c`, and `yguilib_sdl3_test.c`.
5. **Codestyle & consistency (`5.1`, `5.2`)**:
   - Rename `window_id` -> `windowId` in `sdl3.d`.
   - Apply `extern(C)` consistently on all C-ABI structs/union in `sdl3.d`.
   - Align module doc comments with Meson target names (`yguilib_sdl3*`).
6. **Tests (`6.1`)**:
   - Clean up `sdl3.d` unittest (remove SDL calls made without `init()`).
   - Add null-safe smoke unittests in `sdl3_image.d` and `sdl3_ttf.d`.

## Verification

- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
- Confirm `yguilib_sdl3_test` and `yguilib_test` pass with >= baseline
  module count.
