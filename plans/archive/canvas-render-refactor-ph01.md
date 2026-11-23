# ph01: Test infrastructure (review 4.11, 5.5, test part of 5.1)

Overview: `plans/canvas-render-refactor.md`. Review:
`documentation/canvas-render-review.md`. Paths are relative to
`yguilib/source/yguilib/render/`.

Goal: shrink `canvas/package.d` (2939 lines) and remove duplicated GL
test boilerplate before later phases edit it. Behaviour does not change.

## Steps

1. Read every `unittest` block in `canvas/package.d` (starting around
   line 1359) and `package.d` (around lines 1167, 1192, 1808, 1901
   and 2016). List the helpers that are copied between blocks, such as
   `px`, `isRgb`, `near`, `rectPath`, `bounds` and the
   window/renderer setup.
2. Create `internal/gl_test_util.d`:
   - `module yguilib.render.internal.gl_test_util;`, all content inside
     `version (unittest):`, with `package(yguilib)` visibility, and a
     module doc comment.
   - `struct GlTestWindow`, which creates the hidden window, GL context
     and `Renderer` the way the existing tests do. Copy the setup
     exactly. It exposes `renderer`/`canvas` accessors and a
     `destroy()` method. Teardown must end open render targets
     (`while (r.inTarget()) r.endTarget();`) after the `destroy()`
     calls. Each test should declare
     `scope(exit) w.destroy();` and then `scope(exit) w.endTargets();`
     (see AGENTS.md). Document this order in the struct's doc comment.
   - The shared helpers, with no default parameters. A helper that had
     `int ch = 0` becomes two functions, or takes the channel
     explicitly.
   - Replace `lit(int c, out int x0, out int x1)` with a function that
     returns `struct LitSpan { int x0; int x1; }`.
3. Create `canvas/package_test.d`
   (`module yguilib.render.canvas.package_test;`, all of it
   `version (unittest):`). Move every Canvas `unittest` block, with its
   section comments, from `canvas/package.d` into it unchanged except
   for the helper calls. Add the imports it needs. The tests only use
   public or `package(yguilib)` API. If one needs a private member, make
   that member `package(yguilib)` with a comment rather than keep the
   test in place.
4. In `package.d`, switch its unittests to `gl_test_util` and delete the
   local helper copies. Keep those tests in `package.d`.
5. Add both new files to the yguilib source list in
   `yguilib/meson.build`, next to the other render files. Make sure the
   shared `test_main.d` test executable compiles them. Do not add a
   `main` stub.
6. Delete the old helper copies from `canvas/package.d`.

## Verification

- `ninja -C _build && timeout 300 meson test -C _build` is green.
- Compare the number of unittests run before and after this phase.
  Before you start, note the summary line of the yguilib test target
  (run the test binary directly with a timeout if meson hides it). It
  must be the same.
- `canvas/package.d` is about 1350 lines. No line exceeds 80 columns.
