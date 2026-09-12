# Agent Guidelines for yvidtrim

`yvidtrim` is a video trimming tool written in the D programming language with custom, private C wrapper libraries interfacing with external C/C++ dependencies (e.g., SDL3, FFmpeg).

---

## 1. Build and Test Commands

The project uses **Meson** and **Ninja** as its primary build system.

```bash
# Initial configuration / setup (generates compile_commands.json in _build)
meson setup _build .

# Build the project
ninja -C _build

# Run all test suites
meson test -C _build

# Reconfigure if meson.build files change
meson setup --reconfigure _build .
```

> **Note on `dub.json`**: `dub.json` is maintained strictly for IDE/LSP code completion (e.g., `serve-d`, `DCD`). Do not use `dub build` or `dub run` to build or run the main application.

---

## 2. Project Architecture & C Wrapper Design

To maintain long-term stability and resilience across varying external library
versions, `yvidtrim` **never** uses full auto-generated C-to-D bindings or
directly imports external C headers into D.

### The Wrapper Pattern
- **Private C Libraries (`yvidtrim-clibs/`, `yguilib-clibs/`)**: External C/C++
  libraries are wrapped inside custom static C libraries that expose a minimal,
  meaningful C API.
- **Opaque Handles & Types**: Third-party types, structs, and pointers are kept
  opaque in wrapper interfaces to avoid leaking third-party header dependencies
  into D code.
- **D Interface Bindings (`source/yvidtrim/clibs/`, `source/yguilib/clibs/`)**:
  For each wrapper library, matching `extern(C)` declarations are placed in
  `source/<proj>/clibs/<libname>.d`.
- **OpenGL ES Loader (`glad2gles31/`)**: OpenGL ES 3.1 functions are used via
  `glad2gles31`.

### Naming Conventions for Wrappers
| Component | Convention | Example |
| :--- | :--- | :--- |
| **C Library Directory / Base Name** | `<proj>_<libname>` | `yvidtrim_sdl3`, `yguilib_sdl3` |
| **C Header File** | `<proj>-clibs/<proj>_<libname>.h` | `yvidtrim-clibs/yvidtrim_sdl3.h` |
| **C Source File** | `<proj>-clibs/<proj>_<libname>.c` | `yvidtrim-clibs/yvidtrim_sdl3.c` |
| **C Wrapper Test** | `<proj>-clibs/<proj>_<libname>_test.c` | `yvidtrim-clibs/yvidtrim_sdl3_test.c` |
| **D Binding Module** | `source/<proj>/clibs/<libname>.d` | `source/yvidtrim/clibs/sdl3.d` |
| **Public C Function Symbols** | `<proj>_<libname>_<function_name>` | `yvidtrim_sdl3_hello()` |
| **Public C Types / Structs / Enums** | `<proj>_<libname>_<TypeName>` | `yguilib_sdl3_EventType` |

### Adding a New Wrapper Library Checklist
1. Create header `<proj>-clibs/<proj>_<libname>.h` with `#pragma once` and
   prefixed function prototypes.
2. Create implementation `<proj>-clibs/<proj>_<libname>.c`.
3. Create standalone test `<proj>-clibs/<proj>_<libname>_test.c`.
4. Register library, test executable, and test target in
   `<proj>-clibs/meson.build`.
5. Create D binding file in `source/<proj>/clibs/<libname>.d` with
   `module <proj>.clibs.<libname>;` and matching `extern(C)` signatures.
6. Link the static library into the executable in top-level `meson.build`.

---

## 3. Code Style Guidelines

All code in this repository adheres to `.editorconfig` and `codestyle.md`.

### General Formatting
- **Indentation**: 2 spaces (no tabs).
- **Line Endings**: Unix LF, UTF-8 charset.
- **Line Length**: Max 80 characters per line.
- **Braces**: Opening brace `{` on the same line as declaration (`struct`,
  `class`, `function`, `if`, `while`, etc.).
- **File Names**: All source filenames must be entirely **lowercase** (e.g.,
  `sdl3.d`, `yvidtrim_sdl3.c`).

### D Language Conventions
- **Module names**: Lowercase, matching directory structure
  (`yvidtrim.clibs.sdl3`, `yguilib.clibs.sdl3`).
- **Types / Classes / Structs / Interfaces / Enums**: `PascalCase`.
- **Functions / Methods / Variables / Constants**: `camelCase`.

### C Language Conventions
- **Types / Structs / Enums**: `<proj>_<libname>_<TypeName>` for public wrapper
  types (e.g., `yguilib_sdl3_EventType`, `yguilib_sdl3_Event`), or `PascalCase`
  for internal types.
- **Defines / Enum values / Public constants**: `UPPER_SNAKE_CASE`.
- **Variables / Local constants / Functions**: `snake_case`.
- **Public wrapper symbols**: Must be prefixed with `<proj>_<libname>_`
  (e.g., `yvidtrim_<libname>_`, `yguilib_<libname>_`).

---

## 4. Directory Structure

```
.
├── _build/                     # Meson build directory (contains compile_commands.json)
├── source/
│   ├── yguilib/                # Independent GUI library
│   │   ├── clibs/              # D bindings matching yguilib-clibs headers
│   │   │   └── sdl3.d
│   │   ├── app.d
│   │   ├── controller.d
│   │   ├── events.d
│   │   ├── model.d
│   │   ├── uisystem.d
│   │   └── widget.d
│   └── yvidtrim/               # Main application
│       ├── app.d               # Main D application entry point
│       └── clibs/              # D bindings matching yvidtrim-clibs headers
│           └── sdl3.d
├── glad2gles31/                # GLAD OpenGL ES 3.1 loader static library
│   ├── include/
│   │   ├── KHR/
│   │   │   └── khrplatform.h
│   │   └── glad/
│   │       └── gles2.h
│   ├── src/
│   │   └── gles2.c
│   └── meson.build
├── yguilib-clibs/              # C/C++ private wrapper static libraries for yguilib
│   ├── meson.build
│   ├── yguilib_sdl3.h
│   ├── yguilib_sdl3.c
│   └── yguilib_sdl3_test.c
├── yvidtrim-clibs/             # C/C++ private wrapper static libraries and tests
│   ├── meson.build
│   ├── yvidtrim_sdl3.h
│   ├── yvidtrim_sdl3.c
│   └── yvidtrim_sdl3_test.c
├── .clangd                     # Clangd compilation database pointer
├── .editorconfig               # Editor formatting configuration
├── codestyle.md                # Project coding style reference
├── dub.json                    # DUB file (used only for LSP code completion)
├── meson.build                 # Root Meson build configuration
└── README.md                   # Project documentation
```

---

## 5. Agent Workflow Rules

- **Verify Changes**: Always run `ninja -C _build` and `meson test -C _build` to
  verify compilation and test passes after modifying code.
- **Preserve Documentation**: Retain all existing docstrings, comments, and
  licenses unless explicitly instructed otherwise.
- **Enforce Opaque Boundaries**: Never bypass the `yvidtrim-clibs` or
  `yguilib-clibs` wrapper layer to directly invoke external C/C++ APIs from D.
- **Independence**: `./source/yguilib` is an independent GUI library that uses
  SDL3 (via `yguilib-clibs`). Sources in `./source/yguilib/` and
  `./yguilib-clibs/` must not depend on code from `./source/yvidtrim/` or
  `./yvidtrim-clibs/`.
