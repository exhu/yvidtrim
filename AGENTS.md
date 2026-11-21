# Agent Guidelines for yvidtrim

Video trimming tool in D with private C wrappers for external C/C++ libraries.

## Build & Test
Use **Meson** and **Ninja** (`dub.json` is for IDE/LSP only, do not use `dub`).
```bash
ninja -C _build             # Build
meson test -C _build        # Run tests
meson setup _build .        # Setup (or --reconfigure)
```
- Always run unit tests through `meson test -C _build` (never ad-hoc
  `ldc2 -unittest` commands). Ensure every module with `unittest` blocks is
  covered by a Meson test target using a shared `test_main.d`, and do not add
  per-module `version (unittest) void main()` stubs that block unified test
  executables.

## Architecture & Wrapper Rules
- **No Direct C/C++ in D**: Never import external C headers or auto-bind.
- **Private C Wrappers (`yvidtrim-clibs/`, `yguilib/yguilib-clibs/`)**: Wrap
  third-party libraries in static C libraries with opaque handles and minimal
  APIs.
- **D Bindings**: Put matching `extern(C)` in
  `source/yvidtrim/clibs/<libname>.d` (for `yvidtrim`) or
  `yguilib/source/yguilib/clibs/<libname>.d` (for `yguilib`).
- **Naming**: Public symbols use `<proj>_<libname>_` prefix (files:
  `<proj>_<libname>.[c|h]`, funcs: `yvidtrim_sdl3_hello()`, types:
  `yguilib_sdl3_EventType`).
- **New Wrapper Steps**:
  1. Add header & source in `<proj>-clibs/<proj>_<libname>.[c|h]`
     (under `yguilib/` for `yguilib`).
  2. Add test `<proj>-clibs/<proj>_<libname>_test.c` in
     matching `<proj>-clibs/meson.build`.
  3. Add D binding & link in matching `meson.build`.
- **OpenGL ES**: Only call GLES in D code via `glad2.gles2` (loader and bindings
  in `subprojects/glad2gles31/` and `subprojects/glad2gles31d/`).
- **Independence**: `yguilib/` (sources and wrappers) must not depend on
  `source/yvidtrim/` or `yvidtrim-clibs/`.
- GUI changes, graphics api access is allowed only on main thread, only message passing
between threads via sendAppEvent.
- **Controller Event Delegation & Timers**: Subclasses of `DefaultController`
  that override `handleEvent(AppEvent ev)` must return `super.handleEvent(ev)`
  for unhandled events so quit and window redraw lifecycle events are not
  skipped. Model-sync (`update()`) and timer-driven animations (`tick(float dt)`
  or `WidgetSystem` `SystemPhase.update`) are invoked directly in Phase 2; use
  `TimerControl` (`startCallbackTimer` / `startControllerTimer` /
  `startSystemTimer` / `stopTimer` / `startTickTimer`) for active
  animations and stop timers when idle so `SDL_WaitEvent` sleeps at 0% CPU.
- **Pointer Motion Fidelity**: Never merge or coalesce `mouseMotion` events
  into a single vector or endpoint; curved cursor sweeps within one frame must
  hit-test every waypoint in FIFO order, and hover-animated controls should
  latch sub-frame `mouseEnter` + `mouseLeave` pulses without rendering per
  motion packet.
- ARCHITECTURE.md: The system's conceptual and structural reality (module
  dependencies, invariants, topologies, and patterns, data flow).
- Keep ARCHITECTURE.md updated whenever adding new modules, altering directory
  structures, or changing core data flows.
- Keep ARCHITECTURE.md under 250 lines.


## Code Style & Workflow
Adhere to `.editorconfig` and `codestyle.md`:
- 2-space indent, LF, max 80 chars/line, opening `{` on the same line.
- Filenames lowercase only.
- D naming: modules lowercase, types `PascalCase`, funcs/vars `camelCase`.
- C naming: types `PascalCase`, defines/enums `UPPER_SNAKE_CASE`, functions/vars
  `snake_case`.
- **Verify**: Always run `ninja -C _build && meson test -C _build`.
- **Preserve**: Keep existing docstrings and comments.

## Skills & Automation
- Skill helper scripts must be written in D using the standard library.
- Launch skill scripts using `rdmd` (e.g., `rdmd .agents/skills/.../script.d`).

## Markdown documentation
Use ascii for diagrams in `.md` files, e.g. for plans.
Keep line length 80 characters max whenever possible.

## Logs
std.logger is used with log being redirected to SDL, so to see logs when
running guidemo, yvidtrim need to set `SDL_LOGGING` env var, e.g.
```
SDL_LOGGING=app=trace ./_build/yvidtrim
```

## Planning
Ask questions on missing information, confusing topics, available options.
For multiple valid options propose a recommended one. Update TODO.md by removing
the completed item if it is refered to in the prompt, if TODO.md is not mentioned,
propose to update it as part of the implementation plan.
