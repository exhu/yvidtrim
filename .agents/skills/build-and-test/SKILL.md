---
name: build-and-test
description: >-
  Standardized build and test execution for yvidtrim and yguilib with Meson and
  Ninja, supporting reconfigure, target selection, and failure log extraction.
---

# Build and Test Runner

This skill provides a standardized tool to compile and test `yvidtrim` and
`yguilib` according to
[AGENTS.md](file:///home/yur/agy-projects/yvidtrim/AGENTS.md).

## Core Script

The build-and-test runner is implemented in D and executed via `rdmd`:

```bash
rdmd .agents/skills/build-and-test/scripts/run_verify.d [options]
```

## Features

- **Sequential Pipeline**: Runs `ninja -C _build` followed by
  `meson test -C _build`.
- **Targeted Testing**: Supports running individual tests (e.g. `--test
  yguilib_test`).
- **Failure Diagnostics**: Automatically inspects `testlog.txt` when a test
  fails and prints the failure log excerpt and stack trace.
- **Environment Management**: Supports reconfiguring Meson (`--reconfigure`) and
  cleaning build artifacts (`--clean`).

## CLI Usage

### Build and Run All Tests
```bash
rdmd .agents/skills/build-and-test/scripts/run_verify.d
```

### Run Tests Only (Skip Recompilation)
```bash
rdmd .agents/skills/build-and-test/scripts/run_verify.d --test-only
```

### Run a Specific Test Target with Verbose Output
```bash
rdmd .agents/skills/build-and-test/scripts/run_verify.d \
  --test yguilib_test --verbose
```

### Full Reconfigure, Clean, and Rebuild
```bash
rdmd .agents/skills/build-and-test/scripts/run_verify.d --reconfigure --clean
```

## Options

- `--reconfigure`: Reconfigure Meson build directory.
- `--build-only`: Compile with Ninja only without testing.
- `--test-only`: Run tests only without rebuilding.
- `--verbose`: Run tests in verbose mode (`-v`).
- `--clean`: Run `ninja clean` before building.
- `--test <name>`: Run a specific test name.
- `-h`, `--help`: Display help and options.
