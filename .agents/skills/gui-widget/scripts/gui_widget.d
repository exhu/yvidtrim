#!/usr/bin/env rdmd
/**
 * Lists, audits, and scaffolds GUI widgets, components, and builders across
 * yguilib, guidemo, and yvidtrim.
 */
module gui_widget;

import std.algorithm : canFind, filter;
import std.array : array;
import std.conv : to;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.stdio : stderr, write, writefln, writeln;

import widget_scaffold : runScaffoldCommand, ScaffoldOptions;
import widget_scan;

struct CliOptions {
  bool widgets = false;
  bool components = false;
  bool constructors = false;
  bool tests = false;
  bool list = false;
  bool audit = false;
  bool summary = false;
  bool json = false;
  bool help = false;
  string filterTarget = null;
  ScaffoldOptions scaffold;
}

struct ScanResults {
  size_t fileCount;
  CallSite[] callSites;
  ComponentUsage[] compUsages;
  OverloadedConstructor[] overloaded;
  CallSite[] testSites;
  InvariantViolation[] violations;
  CustomBuilderInfo[] customBuilders;
  BuilderChain[] chains;
}

int main(string[] args) {
  CliOptions opts;
  try {
    opts = parseCliArgs(args);
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return 1;
  }
  if (opts.help) {
    return 0;
  }
  if (opts.scaffold.name.length > 0) {
    return runScaffoldCommand(opts.scaffold);
  }
  return runScanCommand(opts);
}

private:

CliOptions parseCliArgs(ref string[] args) {
  CliOptions o;
  GetoptResult helpInfo = getopt(
    args,
    "summary|s", "Display high-level summary table", &o.summary,
    "audit|a",
      "Check Widget invariants (errors) and builder chains (warnings)",
      &o.audit,
    "list|l", "List custom *Builder structs and chain counts", &o.list,
    "widgets|w", "List all Widget and WidgetBuilder call sites", &o.widgets,
    "components|c", "List WidgetComponents accesses", &o.components,
    "constructors|k", "Audit classes with multiple constructors",
      &o.constructors,
    "tests|t", "Audit unit tests for WidgetFixture adoption", &o.tests,
    "json|j", "Output summary counts in JSON format", &o.json,
    "filter|f", "Filter scanned files by substring", &o.filterTarget,
    "scaffold", "Scaffold a new widget builder by PascalCase name",
      &o.scaffold.name,
    "tier", "Scaffold tier: inline (default), view, or system",
      &o.scaffold.tier,
    "module|m", "D module name for scaffold (e.g. yvidtrim.transport)",
      &o.scaffold.modName,
    "output|o", "Output file path for scaffold", &o.scaffold.outPath,
    "dry-run|d", "Preview scaffold output without writing to disk",
      &o.scaffold.dryRun
  );
  if (helpInfo.helpWanted) {
    o.help = true;
    defaultGetoptPrinter(
      "Usage: gui_widget.d [options]\n\n"
      ~ "List, audit, and scaffold GUI widgets and builders.\n\nOptions:",
      helpInfo.options
    );
  }
  return o;
}

ScanResults scanSources(string filterTarget) {
  string[] files = collectDSourceFiles([
    "yguilib/source",
    "yguilib/examples",
    "source",
  ]);
  if (filterTarget !is null) {
    files = files.filter!(f => f.canFind(filterTarget)).array;
  }
  ScanResults r;
  r.fileCount = files.length;
  r.callSites = scanWidgetCallSites(files);
  r.compUsages = scanComponentUsages(files);
  r.overloaded = scanOverloadedConstructors(files);
  r.testSites = scanTestsNeedingFixture(files);
  r.violations = checkWidgetInvariants(files);
  r.customBuilders = scanCustomBuilders(files);
  r.chains = scanBuilderChains(files);
  return r;
}

int runScanCommand(CliOptions opts) {
  if (!opts.widgets && !opts.components && !opts.constructors &&
      !opts.tests && !opts.list && !opts.audit && !opts.summary &&
      !opts.json) {
    opts.summary = true;
    opts.audit = true;
  }
  const ScanResults r = scanSources(opts.filterTarget);
  if (opts.json) {
    printJsonSummary(r);
    return 0;
  }
  if (opts.summary) {
    printSummary(r);
  }
  if (opts.list) {
    printBuilderList(r.customBuilders, r.chains);
  }
  if (opts.widgets) {
    printWidgetSites(r.callSites);
  }
  if (opts.components) {
    printComponentUsages(r.compUsages);
  }
  if (opts.constructors) {
    printOverloads(r.overloaded);
  }
  if (opts.tests) {
    printFixtureCandidates(r.testSites);
  }
  if (!opts.audit) {
    return 0;
  }
  printChainAudit(r.chains);
  writeln();
  return printInvariantAudit(r.violations);
}

void printJsonSummary(in ScanResults r) {
  write("{\n");
  writefln("  \"totalFiles\": %d,", r.fileCount);
  writefln("  \"widgetCallSites\": %d,", r.callSites.length);
  writefln("  \"componentUsages\": %d,", r.compUsages.length);
  writefln("  \"overloadedClasses\": %d,", r.overloaded.length);
  writefln("  \"testCallSitesNeedingFixture\": %d,", r.testSites.length);
  writefln("  \"invariantViolations\": %d\n}", r.violations.length);
}

void printSummary(in ScanResults r) {
  writeln("=== Widget Architecture & Refactoring Summary ===");
  writefln("Scanned D files:                   %d", r.fileCount);
  writefln("Widget construction call sites:    %d", r.callSites.length);

  size_t prodSites = 0;
  size_t testCalls = 0;
  foreach (s; r.callSites) {
    if (s.inUnittest) {
      testCalls++;
    } else {
      prodSites++;
    }
  }
  writefln("  - Production call sites:         %d", prodSites);
  writefln("  - Unittest call sites:           %d", testCalls);
  writefln("  - Tests candidate for fixture:   %d", r.testSites.length);
  writefln("WidgetComponents usages:           %d", r.compUsages.length);
  writefln("Classes with >1 constructor:       %d", r.overloaded.length);
  writefln("Invariant violations:              %d", r.violations.length);
  writeln();
}

void printBuilderList(
  in CustomBuilderInfo[] customBuilders,
  in BuilderChain[] chains
) {
  writeln("=== Custom GUI Widget Builders ===");
  foreach (cb; customBuilders) {
    writefln("  %s (%s:%d)", cb.structName, cb.file, cb.line);
  }
  writefln("Total custom builders: %d\n", customBuilders.length);

  size_t prodCount = 0;
  size_t testCount = 0;
  foreach (ch; chains) {
    if (ch.inUnittest) {
      testCount++;
    } else {
      prodCount++;
    }
  }
  writeln("=== WidgetBuilder Chain Summary ===");
  writefln("  Production chains: %d", prodCount);
  writefln("  Unittest chains:   %d", testCount);
  writefln("  Total chains:      %d\n", chains.length);
}

void printWidgetSites(in CallSite[] callSites) {
  writeln("=== Widget Construction Call Sites ===");
  foreach (site; callSites) {
    writefln(
      "%s:%d [%s%s]: %s",
      site.file,
      site.line,
      groupName(site.group),
      site.inUnittest ? ", test" : "",
      site.text
    );
  }
  writeln();
}

void printComponentUsages(in ComponentUsage[] compUsages) {
  writeln("=== WidgetComponents Usages ===");
  foreach (u; compUsages) {
    writefln(
      "%s:%d [%s]: %s",
      u.file,
      u.line,
      u.componentName,
      u.text
    );
  }
  writeln();
}

void printOverloads(in OverloadedConstructor[] overloaded) {
  writeln("=== Classes / Structs with Multiple Constructors ===");
  if (overloaded.length == 0) {
    writeln("None found. All types have single constructor.");
  } else {
    foreach (o; overloaded) {
      writefln(
        "%s: %s '%s' has %d constructors at lines: %s",
        o.file,
        o.kind,
        o.typeName,
        o.lines.length,
        to!string(o.lines)
      );
    }
  }
  writeln();
}

void printFixtureCandidates(in CallSite[] testSites) {
  writeln("=== Unit Tests Candidate for WidgetFixture Migration ===");
  if (testSites.length == 0) {
    writeln("None found. All tests use WidgetFixture or builders.");
  } else {
    foreach (s; testSites) {
      writefln("%s:%d: %s", s.file, s.line, s.text);
    }
    writefln("Total test sites to migrate: %d", testSites.length);
  }
  writeln();
}

void printChainAudit(in BuilderChain[] chains) {
  writeln("=== WidgetBuilder Convention Audit (Production Code) ===");
  size_t missingNameCount = 0;
  size_t missingRectCount = 0;

  foreach (ch; chains) {
    if (ch.inUnittest) {
      continue;
    }
    if (!ch.hasName) {
      missingNameCount++;
      writefln(
        "  [WARN] %s:%d: %s chain missing .name(...)",
        ch.file,
        ch.startLine,
        ch.kind
      );
    }
    if (!ch.hasRect) {
      missingRectCount++;
      writefln(
        "  [WARN] %s:%d: %s chain missing .rect(...)",
        ch.file,
        ch.startLine,
        ch.kind
      );
    }
  }

  if (missingNameCount == 0 && missingRectCount == 0) {
    writeln("  All production WidgetBuilder chains set .name() and .rect().");
  } else {
    writefln(
      "\nSummary: %d chain(s) missing .name(), %d chain(s) missing .rect().",
      missingNameCount,
      missingRectCount
    );
  }
}

/** Returns 1 when any invariant is violated. */
int printInvariantAudit(in InvariantViolation[] violations) {
  writeln("=== Widget Invariant Audit ===");
  if (violations.length == 0) {
    writeln("All Widget architectural invariants satisfied (0 violations).");
    return 0;
  }
  foreach (v; violations) {
    writefln("%s:%d: [%s] %s", v.file, v.line, v.rule, v.message);
  }
  writefln("Total violations: %d", violations.length);
  return 1;
}
