# Phase 5: demo, docs, cleanup

Files: `source/guidemo/pages/canvas_page.d`, `canvas_controller.d`,
`ARCHITECTURE.md`, `TODO.md`, canvas module header docs.

Steps:
1. Add a text demo to the guidemo canvas page: aligned/baseline samples,
   rotated text, gradient fill, stroked text, shadow, maxWidth. Follow the
   existing page structure (see define-gui-widget skill if widgets change).
2. Update canvas module/class docs (text uses TextCache bitmaps; stroke
   ignores caps/joins/dash; direction affects alignment only).
3. Update `ARCHITECTURE.md` (keep < 250 lines).
4. Remove the first item (canvas text support) from `TODO.md`.
5. Run skills: check-codestyle, check-line-length, check-boundaries.
6. `ninja -C _build && timeout 300 meson test -C _build`.
