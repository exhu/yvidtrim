# Agent Guidelines for yvidtrim

Video trimming tool in D with private C wrappers for external C/C++ libraries.

## Build & Test
Use **Meson** and **Ninja** (`dub.json` is for IDE/LSP only, do not use `dub`).
```bash
ninja -C _build             # Build
meson test -C _build        # Run tests
meson setup _build .        # Setup (or --reconfigure)
```

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
