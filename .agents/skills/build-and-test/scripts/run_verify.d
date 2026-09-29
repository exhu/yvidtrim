#!/usr/bin/env rdmd
/**
 * Build and test verification runner for yvidtrim.
 * Wraps Meson and Ninja with diagnostics parsing and targeted test execution.
 */
module run_verify;

import std.algorithm : canFind;
import std.file : exists, readText;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.process : execute, executeShell, spawnProcess, wait;
import std.stdio : stderr, stdin, stdout, writeln, writefln;
import std.string : splitLines, strip;

int runCommand(string[] cmd) {
  writefln("==> Executing: %-(%s %)", cmd);
  auto pid = spawnProcess(cmd, stdin, stdout, stderr);
  return wait(pid);
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

int main(string[] args) {
  bool optReconfigure = false;
  bool optBuildOnly = false;
  bool optTestOnly = false;
  bool optVerbose = false;
  bool optClean = false;
  string optTestName = null;

  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "reconfigure", "Reconfigure Meson build directory", &optReconfigure,
      "build-only", "Compile with Ninja only without testing", &optBuildOnly,
      "test-only", "Run tests only without rebuilding", &optTestOnly,
      "verbose", "Run tests in verbose mode (-v)", &optVerbose,
      "clean", "Run ninja clean before building", &optClean,
      "test", "Run a specific test name", &optTestName
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

  // 1. Reconfigure if requested or if _build doesn't exist
  if (optReconfigure || !exists("_build")) {
    int res = runCommand(["meson", "setup", "_build", ".", "--reconfigure"]);
    if (res != 0) {
      stderr.writeln("Meson setup/reconfigure failed.");
      return res;
    }
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
      stderr.writeln("Ninja build failed. Review compiler diagnostics above.");
      return res;
    }
    writeln("Build succeeded.");
  }

  // 4. Test step
  if (!optBuildOnly) {
    string[] testCmd = ["meson", "test", "-C", "_build"];
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
