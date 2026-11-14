#!/usr/bin/env rdmd
/**
 * Refactoring, auditing, and analysis tool for Widget and WidgetComponents.
 *
 * Scans, classifies, and verifies Widget construction call sites,
 * WidgetComponent usages, constructor overloading rules, and test fixture
 * adoption across yguilib, guidemo, and yvidtrim.
 */
module refactor_widget;

import std.algorithm : canFind, countUntil, endsWith, filter, sort, startsWith;
import std.array : array, join;
import std.conv : to;
import std.file : dirEntries, exists, isFile, readText, SpanMode;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : baseName, buildNormalizedPath, extension;
import std.regex : ctRegex, matchFirst;
import std.stdio : stderr, write, writefln, writeln;
import std.string : format, indexOf, splitLines, strip;

enum TargetGroup {
  yguilibPublic,
  yguilibInternal,
  guidemo,
  yvidtrim,
  unknown
}

TargetGroup classifyPath(string path) {
  if (path.canFind("yguilib/source/yguilib/internal")) {
    return TargetGroup.yguilibInternal;
  }
  if (path.canFind("yguilib/source/yguilib")) {
    return TargetGroup.yguilibPublic;
  }
  if (path.canFind("source/guidemo")) {
    return TargetGroup.guidemo;
  }
  if (path.canFind("source/yvidtrim")) {
    return TargetGroup.yvidtrim;
  }
  return TargetGroup.unknown;
}

string groupName(TargetGroup g) {
  final switch (g) {
  case TargetGroup.yguilibPublic:
    return "yguilib (public)";
  case TargetGroup.yguilibInternal:
    return "yguilib (internal)";
  case TargetGroup.guidemo:
    return "guidemo";
  case TargetGroup.yvidtrim:
    return "yvidtrim";
  case TargetGroup.unknown:
    return "other";
  }
}

struct CallSite {
  string file;
  size_t line;
  string text;
  bool inUnittest;
  TargetGroup group;
}

struct ComponentUsage {
  string file;
  size_t line;
  string componentName;
  string text;
  bool isCustom;
}

struct OverloadedConstructor {
  string file;
  string typeName;
  string kind; // "class" or "struct"
  size_t[] lines;
}

struct InvariantViolation {
  string file;
  size_t line;
  string rule;
  string message;
}

/**
 * Scans source files and discovers Widget and WidgetBuilder call sites.
 */
CallSite[] scanWidgetCallSites(string[] files) {
  CallSite[] sites;

  foreach (file; files) {
    if (!exists(file) || !isFile(file)) {
      continue;
    }
    string content = readText(file);
    string[] lines = content.splitLines();
    bool inUnittest = false;
    int braceDepth = 0;
    int unittestBraceDepth = -1;

    foreach (size_t idx, string line; lines) {
      string trimmed = line.strip();

      // Track unittest scope
      if (trimmed.startsWith("unittest") && trimmed.canFind("{")) {
        inUnittest = true;
        unittestBraceDepth = braceDepth;
      }
      foreach (c; line) {
        if (c == '{') {
          braceDepth++;
        } else if (c == '}') {
          braceDepth--;
          if (inUnittest && braceDepth <= unittestBraceDepth) {
            inUnittest = false;
            unittestBraceDepth = -1;
          }
        }
      }

      if (trimmed.startsWith("//") || trimmed.startsWith("*")) {
        continue;
      }

      // Check for Widget and WidgetBuilder creations
      if (trimmed.canFind("new Widget(") ||
          trimmed.canFind(".makeWidget(") ||
          trimmed.canFind("WidgetBuilder.make(") ||
          trimmed.canFind("WidgetBuilder(") ||
          trimmed.canFind("flexRow(") ||
          trimmed.canFind("flexColumn(")) {
        sites ~= CallSite(
          file,
          idx + 1,
          trimmed,
          inUnittest,
          classifyPath(file)
        );
      }
    }
  }

  return sites;
}

/**
 * Scans source files for WidgetComponents usages.
 */
ComponentUsage[] scanComponentUsages(string[] files) {
  ComponentUsage[] usages;

  string[] knownComponents = [
    "background", "border", "textLabel", "customDraw",
    "flexContainer", "size", "anchor",
    "scrollableArea", "view", "focus", "defaultButton",
    "keyboardEvent", "mouseEvent", "widgetArray"
  ];

  foreach (file; files) {
    if (!exists(file) || !isFile(file)) {
      continue;
    }
    string content = readText(file);
    string[] lines = content.splitLines();

    foreach (size_t idx, string line; lines) {
      string trimmed = line.strip();
      if (trimmed.startsWith("//") || trimmed.startsWith("*")) {
        continue;
      }

      foreach (comp; knownComponents) {
        string pattern = ".components." ~ comp;
        if (trimmed.canFind(pattern)) {
          usages ~= ComponentUsage(
            file,
            idx + 1,
            comp,
            trimmed,
            false
          );
        }
      }

      if (trimmed.canFind(".components.set") ||
          trimmed.canFind(".components.get") ||
          trimmed.canFind(".components.has")) {
        usages ~= ComponentUsage(
          file,
          idx + 1,
          "custom(set/get/has)",
          trimmed,
          true
        );
      }
    }
  }

  return usages;
}

/**
 * Finds classes and structs that define > 1 constructor (overloading).
 */
OverloadedConstructor[] scanOverloadedConstructors(string[] files) {
  OverloadedConstructor[] overloads;

  auto typeDeclRe = ctRegex!(r"^(final\s+)?(class|struct)\s+([A-Za-z0-9_]+)");
  auto ctorRe = ctRegex!(r"^\s*this\s*\(");

  foreach (file; files) {
    if (!exists(file) || !isFile(file)) {
      continue;
    }
    string content = readText(file);
    string[] lines = content.splitLines();

    string currentType = null;
    string currentKind = null;
    size_t[] ctorLines;
    int typeBraceDepth = -1;
    int braceDepth = 0;

    foreach (size_t idx, string line; lines) {
      string trimmed = line.strip();

      // Check type declaration
      auto mType = matchFirst(trimmed, typeDeclRe);
      if (!mType.empty && typeBraceDepth == -1) {
        currentKind = mType[2];
        currentType = mType[3];
        typeBraceDepth = braceDepth;
        ctorLines = null;
      }

      // Check constructor
      auto mCtor = matchFirst(line, ctorRe);
      if (!mCtor.empty && currentType !is null) {
        // Skip @disable this();
        if (!trimmed.canFind("@disable")) {
          ctorLines ~= (idx + 1);
        }
      }

      // Track braces
      foreach (c; line) {
        if (c == '{') {
          braceDepth++;
        } else if (c == '}') {
          braceDepth--;
          if (typeBraceDepth != -1 && braceDepth <= typeBraceDepth) {
            if (ctorLines.length > 1) {
              overloads ~= OverloadedConstructor(
                file,
                currentType,
                currentKind,
                ctorLines.dup
              );
            }
            currentType = null;
            currentKind = null;
            typeBraceDepth = -1;
            ctorLines = null;
          }
        }
      }
    }
  }

  return overloads;
}

/**
 * Scans unit tests for direct `new Widget(...)` calls instead of WidgetFixture.
 */
CallSite[] scanTestsNeedingFixture(string[] files) {
  CallSite[] sites;
  foreach (site; scanWidgetCallSites(files)) {
    if (site.inUnittest && site.text.canFind("new Widget(")) {
      // Exclude test_fixture.d itself
      if (!site.file.canFind("test_fixture.d")) {
        sites ~= site;
      }
    }
  }
  return sites;
}

/**
 * Audits invariants:
 *  - Parameterless new Widget()
 *  - Direct children appending (w.children ~= ...) outside Widget class
 */
InvariantViolation[] checkWidgetInvariants(string[] files) {
  InvariantViolation[] violations;

  foreach (file; files) {
    if (!exists(file) || !isFile(file)) {
      continue;
    }
    string content = readText(file);
    string[] lines = content.splitLines();

    foreach (size_t idx, string line; lines) {
      string trimmed = line.strip();
      if (trimmed.startsWith("//") || trimmed.startsWith("*")) {
        continue;
      }

      // Invariant: no parameterless new Widget()
      if (trimmed.canFind("new Widget()")) {
        violations ~= InvariantViolation(
          file,
          idx + 1,
          "No parameterless Widget construction",
          "Widget requires explicit uId; parameterless new Widget() is " ~
          "forbidden."
        );
      }

      // Invariant: children ~= outside widget/package.d
      if (trimmed.canFind(".children ~=") &&
          !file.endsWith("widget/package.d")) {
        violations ~= InvariantViolation(
          file,
          idx + 1,
          "Encapsulated child management",
          "Direct children manipulation '" ~ trimmed ~
          "' is forbidden. Use Widget parent APIs."
        );
      }
    }
  }

  return violations;
}

string[] collectDSourceFiles(string[] searchDirs) {
  string[] dFiles;
  foreach (dir; searchDirs) {
    if (!exists(dir)) {
      continue;
    }
    foreach (entry; dirEntries(dir, SpanMode.depth)) {
      if (entry.isFile && extension(entry.name) == ".d") {
        dFiles ~= buildNormalizedPath(entry.name);
      }
    }
  }
  return dFiles;
}

int main(string[] args) {
  bool optWidgets = false;
  bool optComponents = false;
  bool optConstructors = false;
  bool optTests = false;
  bool optAudit = false;
  bool optSummary = false;
  bool optJson = false;
  string filterTarget = null;

  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "widgets|w", "List all Widget and WidgetBuilder call sites", &optWidgets,
      "components|c", "List WidgetComponents accesses", &optComponents,
      "constructors|k", "Audit classes with multiple constructors",
        &optConstructors,
      "tests|t", "Audit unit tests for WidgetFixture adoption", &optTests,
      "audit|a", "Check Widget architectural invariants", &optAudit,
      "summary|s", "Display high-level summary table", &optSummary,
      "json|j", "Output results in JSON format", &optJson,
      "filter|f", "Filter files by substring", &filterTarget
    );
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return 1;
  }

  if (helpInfo.helpWanted) {
    defaultGetoptPrinter(
      "Usage: refactor_widget.d [options]\n\n" ~
      "Widget & WidgetComponent refactoring, inspection, and verification " ~
      "tool.\n\nOptions:",
      helpInfo.options
    );
    return 0;
  }

  string[] searchDirs = ["yguilib/source", "source"];
  string[] files = collectDSourceFiles(searchDirs);
  if (filterTarget !is null) {
    files = files.filter!(f => f.canFind(filterTarget)).array;
  }

  // Default mode: if nothing specified, show summary and audit
  if (!optWidgets && !optComponents && !optConstructors &&
      !optTests && !optAudit && !optSummary && !optJson) {
    optSummary = true;
    optAudit = true;
  }

  auto callSites = scanWidgetCallSites(files);
  auto compUsages = scanComponentUsages(files);
  auto overloaded = scanOverloadedConstructors(files);
  auto testSites = scanTestsNeedingFixture(files);
  auto violations = checkWidgetInvariants(files);

  if (optJson) {
    write("{\n");
    writefln("  \"totalFiles\": %d,", files.length);
    writefln("  \"widgetCallSites\": %d,", callSites.length);
    writefln("  \"componentUsages\": %d,", compUsages.length);
    writefln("  \"overloadedClasses\": %d,", overloaded.length);
    writefln("  \"testCallSitesNeedingFixture\": %d,", testSites.length);
    writefln("  \"invariantViolations\": %d\n}", violations.length);
    return 0;
  }

  if (optSummary) {
    writeln("=== Widget Architecture & Refactoring Summary ===");
    writefln("Scanned D files:                   %d", files.length);
    writefln("Widget construction call sites:    %d", callSites.length);

    size_t prodSites = 0;
    size_t testCalls = 0;
    foreach (s; callSites) {
      if (s.inUnittest) {
        testCalls++;
      } else {
        prodSites++;
      }
    }
    writefln("  - Production call sites:         %d", prodSites);
    writefln("  - Unittest call sites:           %d", testCalls);
    writefln("  - Tests candidate for fixture:   %d", testSites.length);
    writefln("WidgetComponents usages:           %d", compUsages.length);
    writefln("Classes with >1 constructor:       %d", overloaded.length);
    writefln("Invariant violations:              %d", violations.length);
    writeln();
  }

  if (optWidgets) {
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

  if (optComponents) {
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

  if (optConstructors) {
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

  if (optTests) {
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

  if (optAudit) {
    writeln("=== Widget Invariant Audit ===");
    if (violations.length == 0) {
      writeln("All Widget architectural invariants satisfied (0 violations).");
    } else {
      foreach (v; violations) {
        writefln("%s:%d: [%s] %s", v.file, v.line, v.rule, v.message);
      }
      writefln("Total violations: %d", violations.length);
      return 1;
    }
  }

  return 0;
}
