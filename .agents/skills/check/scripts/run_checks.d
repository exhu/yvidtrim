#!/usr/bin/env rdmd
/**
 * Runs the project's static checkers in order, each under a timeout.
 */
module run_checks;

import std.getopt : arraySep, defaultGetoptPrinter, getopt, GetoptResult;
import std.process : spawnProcess, wait;
import std.stdio : stderr, stdin, stdout, writeln, writefln;

/** One static checker, run as `rdmd <script> <args>`. */
struct CheckStep {
  string name;
  string[] args;
}

struct Options {
  string[] only;
  string[] skip;
  bool styleAll = false;
  bool auditWidgets = false;
  bool keepGoing = false;
}

enum scripts = ".agents/skills/check/scripts/";
enum widgetCheck = "gui-widget";

CheckStep[] allSteps(bool styleAll) {
  string[] styleArgs = [scripts ~ "check_style.d"];
  if (styleAll) {
    styleArgs ~= "--all";
  }
  return [
    CheckStep("line-length", [scripts ~ "check_line_length.d"]),
    CheckStep("codestyle", styleArgs),
    CheckStep("null-safety", [scripts ~ "check_null_safety.d"]),
    CheckStep("boundaries", [scripts ~ "check_boundaries.d"]),
    CheckStep("assets", [
      ".agents/skills/manage-assets/scripts/manage_assets.d", "--check"
    ]),
    CheckStep(widgetCheck, [
      ".agents/skills/gui-widget/scripts/gui_widget.d", "--audit"
    ]),
  ];
}

/** The widget audit is opt-in: `--audit-widgets` or `--only gui-widget`. */
CheckStep[] selectSteps(const Options opts) {
  import std.algorithm : canFind;

  CheckStep[] selected;
  foreach (step; allSteps(opts.styleAll)) {
    bool wanted = opts.only.length > 0
      ? opts.only.canFind(step.name)
      : step.name != widgetCheck;
    if (step.name == widgetCheck && opts.auditWidgets) {
      wanted = true;
    }
    if (wanted && !opts.skip.canFind(step.name)) {
      selected ~= step;
    }
  }
  return selected;
}

/** Returns the first name that is not a known check, or null. */
string unknownName(const string[] names) {
  foreach (name; names) {
    bool known = false;
    foreach (step; allSteps(false)) {
      known = known || step.name == name;
    }
    if (!known) {
      return name;
    }
  }
  return null;
}

/**
 * Runs each step under timeout 120, printing one summary line per checker.
 * Stops at the first failure unless `keepGoing` is true; returns 0 when all
 * checkers pass, else the first failing exit code.
 */
int runSteps(const CheckStep[] steps, bool keepGoing) {
  int firstFailure = 0;
  string[] failedNames;
  foreach (step; steps) {
    string[] cmd = ["timeout", "120", "rdmd"] ~ step.args.dup;
    writefln("==> Executing: %-(%s %)", cmd);
    stdout.flush();
    const int res = wait(spawnProcess(cmd, stdin, stdout, stderr));
    if (res == 0) {
      writefln("Check %s: passed.", step.name);
      continue;
    }
    writefln("Check %s: FAILED (exit %d).", step.name, res);
    if (firstFailure == 0) {
      firstFailure = res;
    }
    failedNames ~= step.name;
    if (!keepGoing) {
      break;
    }
  }
  if (firstFailure != 0) {
    writefln("Checks failed (%-(%s, %)).", failedNames);
    return firstFailure;
  }
  writeln("All checks passed.");
  return 0;
}

int main(string[] args) {
  Options opts;
  GetoptResult helpInfo;
  arraySep = ",";
  try {
    helpInfo = getopt(
      args,
      "only", "Run only these checks (comma list or repeated)", &opts.only,
      "skip", "Skip these checks (comma list or repeated)", &opts.skip,
      "style-all", "Pass --all to check_style.d", &opts.styleAll,
      "audit-widgets", "Also run the gui-widget audit", &opts.auditWidgets,
      "keep-going", "Run all checkers instead of stopping early",
        &opts.keepGoing
    );
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return 2;
  }

  if (helpInfo.helpWanted) {
    defaultGetoptPrinter(
      "Usage: rdmd run_checks.d [options]\n"
      ~ "Checks: line-length, codestyle, null-safety, boundaries, assets, "
      ~ "gui-widget\n\nOptions:",
      helpInfo.options
    );
    return 0;
  }
  if (args.length > 1) {
    stderr.writeln("Error: unexpected argument: ", args[1]);
    return 2;
  }
  const string bad = unknownName(opts.only ~ opts.skip);
  if (bad !is null) {
    stderr.writeln("Error: unknown check: ", bad);
    return 2;
  }
  const CheckStep[] steps = selectSteps(opts);
  if (steps.length == 0) {
    stderr.writeln("Error: no checks selected.");
    return 2;
  }
  return runSteps(steps, opts.keepGoing);
}
