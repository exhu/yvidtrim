/**
 * Source scanners for Widget call sites, components, constructors,
 * invariants, WidgetBuilder chains, and custom *Builder structs.
 */
module widget_scan;

import std.algorithm : canFind, endsWith, startsWith;
import std.file : dirEntries, exists, isFile, readText, SpanMode;
import std.path : buildNormalizedPath, extension;
import std.regex : ctRegex, matchFirst;
import std.string : splitLines, strip;

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

struct BuilderChain {
  string file;
  size_t startLine;
  size_t endLine;
  string kind; // "WidgetBuilder.make" or ".child"
  bool hasName;
  bool hasRect;
  bool inUnittest;
}

struct CustomBuilderInfo {
  string file;
  size_t line;
  string structName;
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
      updateBraceDepth(line, braceDepth, inUnittest, unittestBraceDepth);

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

/**
 * Scans files for custom *Builder structs (excluding WidgetBuilder and
 * event builders).
 */
CustomBuilderInfo[] scanCustomBuilders(string[] files) {
  CustomBuilderInfo[] builders;
  auto structRe = ctRegex!(r"^\s*struct\s+([A-Za-z0-9_]*Builder)\b");

  foreach (file; files) {
    if (!exists(file) || !isFile(file)) {
      continue;
    }
    const string[] lines = readText(file).splitLines();
    foreach (size_t idx, string line; lines) {
      auto m = matchFirst(line, structRe);
      if (!m.empty) {
        const string name = m[1];
        if (name != "WidgetBuilder" && !name.endsWith("EventBuilder")) {
          builders ~= CustomBuilderInfo(file, idx + 1, name);
        }
      }
    }
  }
  return builders;
}

/**
 * Scans files for WidgetBuilder.make(...) and .child(...) chains and checks
 * whether .name(...) and .rect(...) are invoked before the statement ends.
 */
BuilderChain[] scanBuilderChains(string[] files) {
  BuilderChain[] chains;
  foreach (file; files) {
    if (!exists(file) || !isFile(file) || file.endsWith("widget/builder.d")) {
      continue;
    }
    chains ~= scanFileBuilderChains(file, readText(file).splitLines());
  }
  return chains;
}

private:

bool hasGeometryCall(string line) {
  return line.canFind(".rect(") ||
    line.canFind(".bounds(") ||
    line.canFind(".pos(") ||
    line.canFind(".size(") ||
    line.canFind(".fixedSize(");
}

BuilderChain[] scanFileBuilderChains(string file, const string[] lines) {
  BuilderChain[] chains;
  bool inUnittest = false;
  int braceDepth = 0;
  int unittestBraceDepth = -1;

  foreach (size_t idx, string line; lines) {
    const string trimmed = line.strip();
    if (trimmed.startsWith("unittest") && trimmed.canFind("{")) {
      inUnittest = true;
      unittestBraceDepth = braceDepth;
    }
    updateBraceDepth(line, braceDepth, inUnittest, unittestBraceDepth);

    if (trimmed.startsWith("//") || trimmed.startsWith("*")) {
      continue;
    }
    if (trimmed.canFind("WidgetBuilder.make(")) {
      chains ~= extractChain(
        file,
        lines,
        idx,
        "WidgetBuilder.make",
        inUnittest
      );
    } else if (
      trimmed.canFind(".child(") && trimmed.canFind("WidgetBuilder")
    ) {
      chains ~= extractChildBlock(file, lines, idx, inUnittest);
    }
  }
  return chains;
}

void updateBraceDepth(
  string line,
  ref int braceDepth,
  ref bool inUnittest,
  ref int unittestBraceDepth
) {
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
}

BuilderChain extractChain(
  string file,
  const string[] lines,
  size_t startIdx,
  string kind,
  bool inUnittest
) {
  bool hasName = false;
  bool hasRect = false;
  size_t endIdx = startIdx;
  int parenDepth = 0;

  for (size_t i = startIdx; i < lines.length && i < startIdx + 60; ++i) {
    const string t = lines[i].strip();
    if (t.canFind(".name(")) {
      hasName = true;
    }
    if (hasGeometryCall(t)) {
      hasRect = true;
    }
    foreach (c; t) {
      if (c == '(') {
        parenDepth++;
      } else if (c == ')') {
        parenDepth--;
      }
    }
    endIdx = i;
    if (parenDepth <= 0 && (t.canFind(".build()") || t.endsWith(";"))) {
      break;
    }
  }

  return BuilderChain(
    file,
    startIdx + 1,
    endIdx + 1,
    kind,
    hasName,
    hasRect,
    inUnittest
  );
}

BuilderChain extractChildBlock(
  string file,
  const string[] lines,
  size_t startIdx,
  bool inUnittest
) {
  bool hasName = false;
  bool hasRect = false;
  size_t endIdx = startIdx;
  int depth = 0;
  bool opened = false;

  for (size_t i = startIdx; i < lines.length && i < startIdx + 50; ++i) {
    const string t = lines[i].strip();
    if (t.canFind(".name(")) {
      hasName = true;
    }
    if (hasGeometryCall(t)) {
      hasRect = true;
    }
    foreach (c; t) {
      if (c == '{') {
        depth++;
        opened = true;
      } else if (c == '}') {
        depth--;
      }
    }
    endIdx = i;
    if (opened && depth <= 0) {
      break;
    }
  }

  return BuilderChain(
    file,
    startIdx + 1,
    endIdx + 1,
    ".child",
    hasName,
    hasRect,
    inUnittest
  );
}
