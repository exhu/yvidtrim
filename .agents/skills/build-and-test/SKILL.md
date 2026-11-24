---
name: build-and-test
description: >-
  Standardized build, timeout-wrapped test execution, and _bench benchmark runs
  for yvidtrim and yguilib with Meson and Ninja, supporting reconfigure, target
  selection, and failure log extraction.
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
  `timeout 300 meson test -C _build`.
- **Targeted Testing**: Supports running individual tests (e.g. `--test
  yguilib_test`).
- **Benchmark Mode**: Configures `_bench` with `-Dbenchmarks=true`, compiles
  via `ninja -C _bench`, and executes `_bench/<path>` under `timeout` (default
  `120`s) with repeatable runs (`--bench-runs`).
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

### Build and Run a Benchmark
```bash
rdmd .agents/skills/build-and-test/scripts/run_verify.d \
  --bench yguilib/textbench --bench-arg batch --bench-runs 2
```

### Full Reconfigure, Clean, and Rebuild
```bash
rdmd .agents/skills/build-and-test/scripts/run_verify.d --reconfigure --clean
```

## Options

- `--reconfigure`: Reconfigure Meson build directory (`_build` or `_bench`).
- `--build-only`: Compile with Ninja only without running tests/benchmark.
- `--test-only`: Run tests or benchmark only without rebuilding.
- `--verbose`: Run tests in verbose mode (`-v`).
- `--clean`: Run `ninja clean` before building.
- `--test <name>`: Run a specific test name.
- `--timeout <sec>`: Timeout in seconds (default: `300` tests, `120` bench).
- `--bench <path>`: Build and run benchmark under `_bench/<path>`.
- `--bench-arg <arg>`: Argument passed to benchmark (repeatable).
- `--bench-runs <N>`: Number of sequential benchmark runs (default: `1`).
- `-h`, `--help`: Display help and options.

## Adding Meson Unit Test Targets

- Never define `version (unittest) void main() {}` inside library, widget, or
  application modules—doing so causes duplicate `main` linker errors when
  modules are combined into unified test binaries (`yguilib_test`,
  `guidemo_test`).
- Use the package's shared `test_main.d`
  (`yguilib/source/yguilib/internal/test_main.d` or
  `source/guidemo/test_main.d`) in `meson.build` with `d_unittest : true`.
- When adding a new module with `unittest` blocks, verify it is included in a
  Meson test target and passes under `meson test -C _build`.
