#!/usr/bin/env rdmd
/**
 * Build and test verification runner for yvidtrim.
 * Wraps Meson and Ninja with diagnostics parsing and targeted test execution.
 */
module run_verify;

import std.conv : to;
import std.file : exists, readText;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : buildPath, isAbsolute, pathSplitter;
import std.process : spawnProcess, wait;
import std.stdio : stderr, stdin, stdout, writeln, writefln;
import std.string : splitLines;

int runCommand(string[] cmd) {
  writefln("==> Executing: %-(%s %)", cmd);
  auto pid = spawnProcess(cmd, stdin, stdout, stderr);
  return wait(pid);
}

int setupMeson(
  string buildDir,
  string[] extraArgs,
  bool forceReconfigure
) {
  bool configured = exists(buildPath(buildDir, "build.ninja"));
  if (!configured) {
    return runCommand(["meson", "setup", buildDir, "."] ~ extraArgs);
  }
  if (forceReconfigure) {
    return runCommand(
      ["meson", "setup", buildDir, ".", "--reconfigure"] ~ extraArgs
    );
  }
  return 0;
}

bool isSafeRelativePath(string relPath) {
  if (relPath.length == 0 || isAbsolute(relPath)) {
    return false;
  }
  foreach (part; pathSplitter(relPath)) {
    if (part == "..") {
      return false;
    }
  }
  return true;
}

void printFailedTestLog() {
  string logPath = "_build/meson-logs/testlog.txt";
  if (!exists(logPath)) {
    return;
  }
  writeln("\n--- Test Failure Log Excerpt ---");
  string content = readText(logPath);
  string[] lines = content.splitLines();
  // Print last 40 lines of test log
  size_t start = lines.length > 40 ? lines.length - 40 : 0;
  foreach (line; lines[start .. $]) {
    writeln(line);
  }
  writeln("--------------------------------\n");
}

int runBenchmark(
  string benchPath,
  string[] benchArgs,
  int benchRuns,
  int optTimeout,
  bool optReconfigure,
  bool optClean,
  bool optTestOnly,
  bool optBuildOnly
) {
  int setupRes = setupMeson("_bench", ["-Dbenchmarks=true"], optReconfigure);
  if (setupRes != 0) {
    stderr.writeln("Meson setup/reconfigure failed for _bench.");
    return setupRes;
  }
  if (optClean) {
    int cleanRes = runCommand(["ninja", "-C", "_bench", "clean"]);
    if (cleanRes != 0) {
      stderr.writeln("Ninja clean failed for _bench.");
      return cleanRes;
    }
  }
  if (!optTestOnly) {
    int buildRes = runCommand(["ninja", "-C", "_bench"]);
    if (buildRes != 0) {
      stderr.writeln("Benchmark build failed.");
      return buildRes;
    }
    writeln("Benchmark build succeeded.");
  }
  if (!optBuildOnly) {
    string benchBin = buildPath("_bench", benchPath);
    if (!exists(benchBin)) {
      stderr.writefln("Benchmark binary not found: %s", benchBin);
      return 1;
    }
    int benchTimeout = optTimeout > 0 ? optTimeout : 120;
    foreach (i; 0 .. benchRuns) {
      if (benchRuns > 1) {
        writefln("\n=== Benchmark Run %d/%d ===", i + 1, benchRuns);
      }
      string[] benchCmd = [
        "timeout", to!string(benchTimeout), benchBin
      ] ~ benchArgs;
      int res = runCommand(benchCmd);
      if (res != 0) {
        stderr.writefln(
          "Benchmark failed on run %d (exit %d).", i + 1, res
        );
        return res;
      }
    }
    writeln("Benchmark completed successfully.");
  }
  return 0;
}

int main(string[] args) {
  bool optReconfigure = false;
  bool optBuildOnly = false;
  bool optTestOnly = false;
  bool optVerbose = false;
  bool optClean = false;
  string optTestName = null;
  int optTimeout = 0;
  string optBench = null;
  string[] optBenchArgs;
  int optBenchRuns = 1;

  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "reconfigure", "Reconfigure Meson build directory", &optReconfigure,
      "build-only", "Compile with Ninja only without testing", &optBuildOnly,
      "test-only", "Run tests only without rebuilding", &optTestOnly,
      "verbose", "Run tests in verbose mode (-v)", &optVerbose,
      "clean", "Run ninja clean before building", &optClean,
      "test", "Run a specific test name", &optTestName,
      "timeout",
        "Timeout in seconds (default: 300 tests, 120 bench)",
        &optTimeout,
      "bench", "Build and run benchmark under _bench/<path>", &optBench,
      "bench-arg",
        "Argument passed to benchmark (repeatable)",
        &optBenchArgs,
      "bench-runs",
        "Number of sequential benchmark runs (default: 1)",
        &optBenchRuns
    );
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return 1;
  }

  if (helpInfo.helpWanted) {
    defaultGetoptPrinter(
      "Usage: run_verify.d [options]\n"
      ~ "Runs Ninja build and Meson test suite with error reporting.\n\n"
      ~ "Options:",
      helpInfo.options
    );
    return 0;
  }

  if (optTimeout < 0) {
    stderr.writeln("Error: --timeout must be non-negative.");
    return 1;
  }
  if (optBenchRuns < 1) {
    stderr.writeln("Error: --bench-runs must be at least 1.");
    return 1;
  }
  if (optBench !is null && !isSafeRelativePath(optBench)) {
    stderr.writeln("Error: --bench must be a safe relative path.");
    return 1;
  }

  if (optBench !is null) {
    return runBenchmark(
      optBench,
      optBenchArgs,
      optBenchRuns,
      optTimeout,
      optReconfigure,
      optClean,
      optTestOnly,
      optBuildOnly
    );
  }

  // 1. Setup or reconfigure _build
  int setupRes = setupMeson("_build", [], optReconfigure);
  if (setupRes != 0) {
    stderr.writeln("Meson setup/reconfigure failed.");
    return setupRes;
  }

  // 2. Clean if requested
  if (optClean) {
    int res = runCommand(["ninja", "-C", "_build", "clean"]);
    if (res != 0) {
      stderr.writeln("Ninja clean failed.");
      return res;
    }
  }

  // 3. Build step
  if (!optTestOnly) {
    int res = runCommand(["ninja", "-C", "_build"]);
    if (res != 0) {
      stderr.writeln(
        "Ninja build failed. Review compiler diagnostics above."
      );
      return res;
    }
    writeln("Build succeeded.");
  }

  // 4. Test step
  if (!optBuildOnly) {
    int testTimeout = optTimeout > 0 ? optTimeout : 300;
    string[] testCmd = [
      "timeout", to!string(testTimeout), "meson", "test", "-C", "_build"
    ];
    if (optVerbose) {
      testCmd ~= "-v";
    }
    if (optTestName !is null) {
      testCmd ~= optTestName;
    }

    int res = runCommand(testCmd);
    if (res != 0) {
      stderr.writeln("Meson tests failed.");
      printFailedTestLog();
      return res;
    }
    writeln("All tests passed successfully.");
  }

  return 0;
}
