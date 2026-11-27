# Agent Guidelines for yvidtrim

Video trimming tool in D; external C/C++ libraries go through private C
wrappers. Three code trees: `source/yvidtrim/` (the app), `source/guidemo/`
(GUI showcase and testbed), and `yguilib/` (GUI library).

## Build & Test
Meson + Ninja only (`dub.json` is for IDE/LSP; never run `dub`).
```bash
meson setup _build .                                # or --reconfigure
ninja -C _build && timeout 300 meson test -C _build # verify every change
```
- Tests only via `meson test` (no ad-hoc `ldc2 -unittest`). Every module
  with `unittest` blocks needs a Meson test target using the shared
  `test_main.d`; no per-module `version (unittest) void main()`.
- Prefer `rdmd .agents/skills/build-and-test/scripts/run_verify.d`
  (with `--checks` for static checks + build + tests) over raw chained
  `ninja && timeout ... meson test` commands.
- Always use a timeout and never tee test output to files: an assert in
  `scope(exit)` during unwinding can loop forever (100% CPU, fills `/tmp`).
  In GL tests, put `while (r.inTarget()) r.endTarget();` in a `scope(exit)`
  declared after the `destroy()` ones.

## Architecture Rules
- **No direct C/C++ in D**: never import C headers or auto-bind. Wrap
  libraries as static C libs with opaque handles and minimal APIs in
  `yvidtrim-clibs/` or `yguilib/yguilib-clibs/`.
- **New wrapper**: `<proj>-clibs/<proj>_<libname>.[c|h]`, test
  `<proj>_<libname>_test.c` in that dir's `meson.build`, D `extern(C)`
  binding in `source/yvidtrim/clibs/<libname>.d` or
  `yguilib/source/yguilib/clibs/<libname>.d`, linked in `meson.build`.
- **Naming**: public symbols prefixed `<proj>_<libname>_`
  (`yvidtrim_sdl3_hello()`, `yguilib_sdl3_EventType`).
- **GLES**: from D only via `glad2.gles2` (`subprojects/glad2gles31[d]/`).
- **Independence**: `yguilib/` must not depend on `source/yvidtrim/`,
  `source/guidemo/`, or `yvidtrim-clibs/`.
- **Threads**: GUI and graphics API on main thread only; cross-thread
  communication only via `sendAppEvent`.
- **Controllers**: `DefaultController` subclasses overriding
  `handleEvent(AppEvent ev)` must return `super.handleEvent(ev)` for
  unhandled events (quit/redraw). Phase 2a: model sync
  (`Controller.update()`, `SystemPhase.update`); Phase 2b: due timers
  (`Controller.onTimer`, `WidgetSystem.onTimer`). Animate via
  `TimerControl.startTimer`/`stopTimer`; stop when idle so `SDL_WaitEvent`
  sleeps at 0% CPU.
- **View/Controller**: create `ModelTracker!M`, then `View(ui, tracker)`,
  then `Controller(ui, tracker, view)`. Controllers never create their View
  or touch `App`/`Window`; `main()` calls
  `app.withRootWidget(view.rootWidget())`. Keeps them headless-testable with
  `makeHeadlessUiSystem()` (`yguilib.uisystem`).
- **Pointer motion**: never coalesce `mouseMotion` events; hit-test every
  waypoint in FIFO order. Hover-animated controls latch sub-frame
  `mouseEnter`+`mouseLeave` pulses without rendering per packet.
- **ARCHITECTURE.md** (modules, invariants, data flow): update it when
  adding modules or changing structure/data flow; keep under 250 lines.

## Code Style
Read `codestyle.md` before writing code; follow it and `.editorconfig`.
Keep existing comments and docstrings.

## Skills & Tooling
- Skill helper scripts: D + stdlib, run with `rdmd .agents/skills/.../x.d`,
  invoked directly (one script call per `run_command` — no shell `for` loops,
  `&&`/`;` chains, `echo`/`awk`/`wc`/`sed`/`grep` wrappers, raw `find`/`ls`
  instead of `inspect-tree`, raw `grep`/`rg` instead of `search-code`, or
  `rm` on scratch files); extend the script if a flag or batch mode is
  missing.
- No inline `python3 -c`/`perl -e` to edit or inspect files; use file tools
  or a D skill script.

## Docs
Markdown: ASCII diagrams, 80-col lines where possible.

## Logs
std.logger goes to SDL; enable with e.g.
`SDL_LOGGING=app=trace ./_build/yvidtrim`.

## Planning
- Plans live in `plans/`: overview `plans/<name>.md` linking verifiable
  phase files `plans/<name>-01.md` ... `-NN.md`, sized to fit context.
  Phase files never use a `-ph` infix (no `-ph01`), even if archived
  plans do.
- Do not read `plans/archive/` unless the user asks for it.
- Run each phase in a fresh subagent given only its phase file; update the
  overview's status after each phase.
- Ask about missing/unclear info; for multiple options, recommend one.
- If the prompt references a TODO.md item, remove it when done; otherwise
  propose a TODO.md update in the plan.
