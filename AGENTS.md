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

To maintain long-term stability and resilience across varying external library versions, `yvidtrim` **never** uses full auto-generated C-to-D bindings or directly imports external C headers into D.

### The Wrapper Pattern
- **Private C Libraries (`yvidtrim-clibs/`)**: External C/C++ libraries are wrapped inside custom static C libraries that expose a minimal, meaningful C API.
- **Opaque Handles & Types**: Third-party types, structs, and pointers are kept opaque in wrapper interfaces to avoid leaking third-party header dependencies into D code.
- **D Interface Bindings (`source/yvidtrim/clibs/`)**: For each wrapper library, matching `extern(C)` declarations are placed in `source/yvidtrim/clibs/<libname>.d`.

### Naming Conventions for Wrappers
| Component | Convention | Example |
| :--- | :--- | :--- |
| **C Library Directory / Base Name** | `yvidtrim_<libname>` | `yvidtrim_sdl3` |
| **C Header File** | `yvidtrim-clibs/yvidtrim_<libname>.h` | `yvidtrim-clibs/yvidtrim_sdl3.h` |
| **C Source File** | `yvidtrim-clibs/yvidtrim_<libname>.c` | `yvidtrim-clibs/yvidtrim_sdl3.c` |
| **C Wrapper Test** | `yvidtrim-clibs/yvidtrim_<libname>_test.c` | `yvidtrim-clibs/yvidtrim_sdl3_test.c` |
| **D Binding Module** | `source/yvidtrim/clibs/<libname>.d` | `source/yvidtrim/clibs/sdl3.d` |
| **Public C Function Symbols** | `yvidtrim_<libname>_<function_name>` | `yvidtrim_sdl3_hello()` |

### Adding a New Wrapper Library Checklist
1. Create header `yvidtrim-clibs/yvidtrim_<libname>.h` with `#pragma once` and prefixed function prototypes.
2. Create implementation `yvidtrim-clibs/yvidtrim_<libname>.c`.
3. Create standalone test `yvidtrim-clibs/yvidtrim_<libname>_test.c`.
4. Register library, test executable, and test target in `yvidtrim-clibs/meson.build`.
5. Create D binding file in `source/yvidtrim/clibs/<libname>.d` with `module yvidtrim.clibs.<libname>;` and matching `extern(C)` signatures.
6. Link the static library into the executable in top-level `meson.build`.

---

## 3. Code Style Guidelines

All code in this repository adheres to `.editorconfig` and `codestyle.md`.

### General Formatting
- **Indentation**: 2 spaces (no tabs).
- **Line Endings**: Unix LF, UTF-8 charset.
- **Line Length**: Max 80 characters per line.
- **Braces**: Opening brace `{` on the same line as declaration (`struct`, `class`, `function`, `if`, `while`, etc.).
- **File Names**: All source filenames must be entirely **lowercase** (e.g., `sdl3.d`, `yvidtrim_sdl3.c`).

### D Language Conventions
- **Module names**: Lowercase, matching directory structure (`yvidtrim.clibs.sdl3`).
- **Types / Classes / Structs / Interfaces / Enums**: `PascalCase`.
- **Functions / Methods / Variables / Constants**: `camelCase`.

### C Language Conventions
- **Types / Structs / Enums**: `PascalCase`.
- **Defines / Enum values / Public constants**: `UPPER_SNAKE_CASE`.
- **Variables / Local constants / Functions**: `snake_case`.
- **Public wrapper symbols**: Must be prefixed with `yvidtrim_<libname>_`.

---

## 4. Directory Structure

```
.
├── _build/                     # Meson build directory (contains compile_commands.json)
├── source/
│   └── yvidtrim/
│       ├── app.d               # Main D application entry point
│       └── clibs/              # D bindings matching yvidtrim-clibs headers
│           └── sdl3.d
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

- **Verify Changes**: Always run `ninja -C _build` and `meson test -C _build` to verify compilation and test passes after modifying code.
- **Preserve Documentation**: Retain all existing docstrings, comments, and licenses unless explicitly instructed otherwise.
- **Enforce Opaque Boundaries**: Never bypass the `yvidtrim-clibs` wrapper layer to directly invoke external C/C++ APIs from D.
- ./source/yguilib is an independet gui library, it must not depend on code from ./source/yvidtrim/
