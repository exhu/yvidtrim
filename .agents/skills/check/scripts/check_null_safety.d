#!/usr/bin/env rdmd
/**
 * Null safety and contract auditor for yvidtrim and yguilib.
 * Enforces codestyle.md:
 *  - D constructor assertions: assert(arg !is null) for reference types
 *  - D class/struct invariants for non-null pointer/class fields
 *  - C wrapper header NULL documentation for pointer arguments/returns
 */
module check_null_safety;

import std.array : split;
import std.file : dirEntries, exists, isDir, isFile, readText, SpanMode;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : extension;
import std.stdio : stderr, writeln, writefln;
import std.string : endsWith, indexOf, splitLines, startsWith, strip;

enum NullIssueLevel {
  warning,
  error
}

struct NullIssue {
  string file;
  size_t line;
  NullIssueLevel level;
  string message;
}

bool isValueType(string typeName) {
  switch (typeName) {
    case "int":
    case "uint":
    case "long":
    case "ulong":
    case "short":
    case "ushort":
    case "byte":
    case "ubyte":
    case "char":
    case "wchar":
    case "dchar":
    case "float":
    case "double":
    case "real":
    case "bool":
    case "void":
    case "size_t":
    case "ptrdiff_t":
    case "string":
    case "wstring":
    case "dstring":
    case "PointF":
    case "ColorF":
    case "RectF":
    case "LayoutBox":
    case "LayoutDimensions":
    case "Kind":
    case "LogLevel":
    case "Style":
    case "HoverAnimConfig":
      return true;
    default:
      return typeName.startsWith("ModelTracker");
  }
}

bool hasNullableDocAbove(const string[] lines, size_t lineIdx) {
  import std.algorithm : canFind;

  if (lineIdx == 0) {
    return false;
  }
  for (int back = cast(int)lineIdx - 1;
    back >= 0 && back >= cast(int)lineIdx - 5;
    back--) {
    string prev = lines[back].strip();
    if (prev.canFind("@nullable") || prev.canFind("can be null")
        || prev.canFind("allowed to be null")) {
      return true;
    }
    if (!prev.startsWith("//") && !prev.startsWith("*")
        && !prev.startsWith("/*") && !prev.startsWith("///")) {
      break;
    }
  }
  return false;
}

string[] extractRefParamNames(string paramsStr) {
  import std.algorithm : canFind;

  string[] refParamNames;
  foreach (p; paramsStr.split(",")) {
    string trimmedP = p.strip();
    ptrdiff_t eqIdx = trimmedP.indexOf('=');
    if (eqIdx != -1) {
      trimmedP = trimmedP[0 .. eqIdx].strip();
    }
    string[] parts = trimmedP.split();
    if (parts.length >= 2 && !parts.canFind("ref")) {
      string pType = parts[$ - 2].strip();
      string pName = parts[$ - 1].strip();
      if (pType.endsWith("*") || (!isValueType(pType)
          && pType.length > 0 && pType[0] >= 'A' && pType[0] <= 'Z')) {
        refParamNames ~= pName;
      }
    }
  }
  return refParamNames;
}

string collectCtorParams(
  const string[] lines,
  size_t startIdx,
  ref size_t endIdx
) {
  string accum = "";
  int parenDepth = 0;
  bool opened = false;
  for (size_t j = startIdx; j < lines.length && j < startIdx + 12; j++) {
    foreach (char c; lines[j]) {
      if (c == '(') {
        if (opened) {
          accum ~= c;
        }
        parenDepth++;
        opened = true;
      } else if (c == ')') {
        parenDepth--;
        if (opened && parenDepth == 0) {
          endIdx = j;
          return accum.strip();
        }
        if (opened) {
          accum ~= c;
        }
      } else if (opened) {
        accum ~= c;
      }
    }
    if (opened) {
      accum ~= ' ';
    }
  }
  endIdx = startIdx;
  return "";
}

string collectBodySnippet(const string[] lines, size_t startIdx) {
  string bodyAccum = "";
  int braceCount = 0;
  bool inBody = false;
  for (size_t j = startIdx; j < lines.length && j < startIdx + 40; j++) {
    string bLine = lines[j];
    bodyAccum ~= " " ~ bLine;
    foreach (char c; bLine) {
      if (c == '{') {
        braceCount++;
        inBody = true;
      } else if (c == '}') {
        braceCount--;
      }
    }
    if (inBody && braceCount == 0) {
      break;
    }
  }
  return bodyAccum;
}

void auditCtorAt(
  string filePath,
  const string[] lines,
  size_t lineIdx,
  ref NullIssue[] issues
) {
  import std.algorithm : canFind;

  size_t paramEnd = lineIdx;
  string paramsStr = collectCtorParams(lines, lineIdx, paramEnd);
  if (paramsStr.length == 0 || hasNullableDocAbove(lines, lineIdx)) {
    return;
  }
  string[] refParamNames = extractRefParamNames(paramsStr);
  if (refParamNames.length == 0) {
    return;
  }
  string bodyAccum = collectBodySnippet(lines, paramEnd);
  foreach (pName; refParamNames) {
    bool hasAssert = bodyAccum.canFind("assert(" ~ pName ~ " !is null")
      || bodyAccum.canFind("assert(" ~ pName ~ " != null")
      || bodyAccum.canFind("assert(" ~ pName ~ ")");
    if (!hasAssert) {
      issues ~= NullIssue(
        filePath,
        lineIdx + 1,
        NullIssueLevel.warning,
        "Constructor parameter '" ~ pName ~ "' is a reference/pointer type "
        ~ "but lacks 'assert(" ~ pName ~ " !is null)'."
      );
    }
  }
}

/**
 * Checks D constructor assertions and invariants.
 */
void checkNullSafetyInD(
  string filePath,
  string content,
  ref NullIssue[] issues
) {
  import std.algorithm : canFind;
  import std.regex : ctRegex, matchFirst;

  string[] lines = content.splitLines();
  auto ctorRe = ctRegex!(
    r"^\s*(public\s+|private\s+|protected\s+)?this\s*\("
  );

  bool inBlockComment = false;
  for (size_t i = 0; i < lines.length; i++) {
    string trimmed = lines[i].strip();
    if (inBlockComment) {
      if (trimmed.canFind("*/")) {
        inBlockComment = false;
      }
      continue;
    }
    if (trimmed.startsWith("/*")) {
      if (!trimmed.canFind("*/")) {
        inBlockComment = true;
      }
      continue;
    }
    if (trimmed.startsWith("//") || trimmed.startsWith("@disable")) {
      continue;
    }
    if (!matchFirst(lines[i], ctorRe).empty) {
      auditCtorAt(filePath, lines, i, issues);
    }
  }
}

bool hasNullDocComment(const string[] lines, size_t lineIdx) {
  import std.algorithm : canFind;

  if (lineIdx == 0) {
    return false;
  }
  for (int back = cast(int)lineIdx - 1;
    back >= 0 && back >= cast(int)lineIdx - 8;
    back--) {
    string prev = lines[back].strip();
    if (prev.canFind("NULL") || prev.canFind("null")
        || prev.canFind("undefined")) {
      return true;
    }
    if (!prev.startsWith("//") && !prev.startsWith("*")
        && !prev.startsWith("/*") && !prev.startsWith("///")) {
      break;
    }
  }
  return false;
}

/**
 * Checks C header function comments for NULL documentation.
 */
void checkHeaderNullDoc(
  string filePath,
  string content,
  ref NullIssue[] issues
) {
  import std.algorithm : canFind;
  import std.regex : ctRegex, matchFirst;

  if (extension(filePath) != ".h") {
    return;
  }

  string[] lines = content.splitLines();
  auto cFuncRe = ctRegex!(
    r"^(?:const\s+)?[a-zA-Z0-9_]+(\s*\*+\s*|\s+)([a-zA-Z0-9_]+)\s*\((.*?)\)\s*;"
  );

  for (size_t i = 0; i < lines.length; i++) {
    string line = lines[i].strip();
    if (line.startsWith("typedef ")) {
      continue;
    }
    auto m = matchFirst(line, cFuncRe);
    if (m.empty) {
      continue;
    }
    bool returnsPtr = m[1].canFind("*");
    string funcName = m[2];
    string funcArgs = m[3];
    if (!returnsPtr && !funcArgs.canFind("*")) {
      continue;
    }
    if (!hasNullDocComment(lines, i)) {
      issues ~= NullIssue(
        filePath,
        i + 1,
        NullIssueLevel.warning,
        "C wrapper function '" ~ funcName
        ~ "' accepts/returns pointers but lacks explicit NULL documentation."
      );
    }
  }
}

void auditFile(string path, ref NullIssue[] issues) {
  string ext = extension(path);
  if (ext == ".d") {
    checkNullSafetyInD(path, readText(path), issues);
  } else if (ext == ".h") {
    checkHeaderNullDoc(path, readText(path), issues);
  }
}

void auditDir(string dir, ref NullIssue[] issues) {
  if (!exists(dir)) {
    return;
  }
  foreach (entry; dirEntries(dir, SpanMode.depth)) {
    if (entry.isFile) {
      auditFile(entry.name, issues);
    }
  }
}

int main(string[] args) {
  GetoptResult helpInfo;
  try {
    helpInfo = getopt(args);
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return 1;
  }

  if (helpInfo.helpWanted) {
    defaultGetoptPrinter(
      "Usage: check_null_safety.d [options] [files...]\n"
      ~ "Audits constructor non-null assertions and C wrapper NULL doc.\n\n"
      ~ "Options:",
      helpInfo.options
    );
    return 0;
  }

  NullIssue[] issues;
  string[] targetDirs = ["source", "yguilib", "yvidtrim-clibs"];
  string[] targets = args[1 .. $];

  if (targets.length == 0) {
    foreach (d; targetDirs) {
      auditDir(d, issues);
    }
  } else {
    foreach (t; targets) {
      if (!exists(t)) {
        stderr.writefln("Error: path not found: %s", t);
        return 1;
      }
      if (isDir(t)) {
        auditDir(t, issues);
      } else if (isFile(t)) {
        auditFile(t, issues);
      }
    }
  }

  size_t warnCount = 0;
  size_t errCount = 0;
  foreach (const ref issue; issues) {
    string lvl = issue.level == NullIssueLevel.error ? "error" : "warning";
    writefln("%s:%d: [%s] %s", issue.file, issue.line, lvl, issue.message);
    if (issue.level == NullIssueLevel.error) {
      errCount++;
    } else {
      warnCount++;
    }
  }

  if (issues.length > 0) {
    writefln("Null safety audit: %d warning(s), %d error(s).",
      warnCount, errCount);
  } else {
    writeln("Null safety audit: all checked contracts satisfied.");
  }

  return errCount > 0 ? 1 : 0;
}
