---
name: wrap-c-lib
description: >-
  Scaffold and integrate private C wrapper libraries and matching D bindings
  for third-party C/C++ libraries (e.g., SDL3, SDL3_ttf, FFmpeg). Use this skill
  when adding, binding, or wrapping external C/C++ libraries into yvidtrim or
  yguilib.
---

# C Wrapper & D Binding Scaffolding

This skill provides the end-to-end workflow for wrapping external C/C++
libraries in private C static libraries and exposing minimal D bindings.

## Architecture Principles

1. **No Direct C/C++ in D**: Never import C headers into D (e.g. ImportC)
   or auto-bind them. Third-party dependencies must stay strictly in C.
2. **Private C Static Wrappers**: External libraries are wrapped in static
   libraries under `<proj>-clibs/` (`yvidtrim-clibs/` for `yvidtrim`,
   `yguilib/yguilib-clibs/` for `yguilib`) with opaque handles, minimal APIs,
   and hidden symbols (`gnu_symbol_visibility : 'hidden'`).
3. **D Bindings**: Hand-written `extern(C)` declarations matching the wrapper
   header are placed in `source/<proj>/clibs/<libname>.d` (or
   `yguilib/source/yguilib/clibs/<libname>.d` for `yguilib`).
4. **Symbol & File Naming**:
   - Files: `<c-dir>/<proj>_<libname>.[c|h]`,
     `<c-dir>/<proj>_<libname>_test.c`,
     `<d-dir>/<libname>.d`.
   - C functions: `<proj>_<libname>_<function_name>`.
   - C types: `<proj>_<libname>_<TypeName>`.
   - C enums / defines: `<PROJ>_<LIBNAME>_<VALUE>`.
   - D modules: `<proj>.clibs.<libname>`.

---

## Quick Start: Scaffolding with `scaffold.d`

Use the D scaffolding script to generate boilerplate files:

```bash
# Usage: rdmd <script> [options] <proj> <libname>
rdmd .agents/skills/wrap-c-lib/scripts/scaffold.d \
  yguilib sdl3_ttf --dep sdl3-ttf
```

Options:
- `--dep <name>`: Pkg-config dependency name for Meson
  (defaults to `<libname>`).
- `--dry-run`: Preview file generation without writing to disk.
- `--force`: Overwrite existing files.

The script scaffolds:
- `<proj>-clibs/<proj>_<libname>.h`
- `<proj>-clibs/<proj>_<libname>.c`
- `<proj>-clibs/<proj>_<libname>_test.c`
- `source/<proj>/clibs/<libname>.d`
- Prints the exact Meson configuration snippets to paste into build files.

---

## Detailed Step-by-Step Workflow

### 1. Define the Minimal C Wrapper API
Edit `<proj>-clibs/<proj>_<libname>.h`:
- Include `#pragma once`.
- Wrap declarations in `extern "C" { ... }` for C++ compatibility.
- Expose only opaque pointer types for third-party objects (e.g.,
  `typedef struct yguilib_sdl3_Window yguilib_sdl3_Window;`).
- Prefix every public function with `<proj>_<libname>_`.

### 2. Implement Wrapper in C
Edit `<proj>-clibs/<proj>_<libname>.c`:
- Include external library headers (e.g., `<SDL3/SDL.h>`,
  `<SDL3_ttf/SDL_ttf.h>`).
- Implement helper conversions, memory lifecycle, and opaque handle unwrapping.
- Keep all external library headers local to the `.c` file whenever possible.

### 3. Write the Standalone C Unit Test
Edit `<proj>-clibs/<proj>_<libname>_test.c`:
- Write a standalone test program executing the wrapper functions.
- Verify initialization, basic operations, and cleanup in C before touching D.

### 4. Register in `<proj>-clibs/meson.build`
Add the dependency, static library, and test target:
```meson
dep_<libname> = dependency('<pkg_name>')

<proj>_<libname>_lib = static_library(
  '<proj>_<libname>',
  ['<proj>_<libname>.c'],
  install : false,
  gnu_symbol_visibility : 'hidden',
  dependencies : [dep_<libname>],
)

<proj>_<libname>_test = executable(
  '<proj>_<libname>_test',
  '<proj>_<libname>_test.c',
  dependencies : [dep_<libname>],
  link_with : <proj>_<libname>_lib,
)
test('<proj>_<libname>', <proj>_<libname>_test)
```

### 5. Write Matching D Bindings
Edit `source/<proj>/clibs/<libname>.d`:
- Module name: `module <proj>.clibs.<libname>;`.
- Declare matching `struct` definitions (opaque or value) and `enum` values.
- Declare matching `extern(C)` functions.

### 6. Link in Meson
- In `meson.build` (or `yguilib/meson.build` for `yguilib`):
  - Add the D binding file to the relevant source list (`yvidtrim_src` or
    `yguilib_src`).
  - Add `<proj>_<libname>_lib` to the `link_with` list of the executable/test.
- `dub.json` is for IDE/LSP only and needs no change: its `sourcePaths`
  already pick up the new module. Never run `dub`.

### 7. Update Docs, Build and Verify
- Add the new wrapper to `ARCHITECTURE.md` (keep it under 250 lines).
- Reconfigure, run the static checks, build, and run the tests (timeout):
```bash
rdmd .agents/skills/build-and-test/scripts/run_verify.d --reconfigure --checks
```
Ensure all tests pass and no symbol visibility or linkage errors occur.
