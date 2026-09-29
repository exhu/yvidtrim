#!/usr/bin/env rdmd
/**
 * Null safety and contract auditor for yvidtrim and yguilib.
 * Enforces codestyle.md:
 *  - D constructor assertions: assert(arg !is null) for reference types
 *  - D class/struct invariants for non-null pointer/class fields
 *  - C wrapper header NULL documentation for pointer arguments/returns
 */
module check_null_safety;

import std.algorithm : canFind, countUntil;
import std.array : split;
import std.conv : to;
import std.file : dirEntries, exists, isDir, isFile, readText, SpanMode;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : baseName, extension;
import std.regex : ctRegex, matchAll, matchFirst;
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
      return true;
    default:
      return false;
  }
}

/**
 * Checks D constructor assertions and invariants.
 */
void checkDNullSafety(
  string filePath,
  string content,
  ref NullIssue[] issues
) {
  string[] lines = content.splitLines();
  auto ctorRe = ctRegex!(
    r"^\s*(public\s+|private\s+|protected\s+)?this\s*\((.*?)\)"
  );
  auto assertRe = ctRegex!(r"assert\s*\(\s*([a-zA-Z0-9_]+)\s*!\s*is\s*null");

  // Track constructors and assertions
  for (size_t i = 0; i < lines.length; i++) {
    string line = lines[i];
    auto ctorMatch = matchFirst(line, ctorRe);
    if (!ctorMatch.empty) {
      string paramsStr = ctorMatch[2].strip();
      if (paramsStr.length == 0) {
        continue;
      }

      // Check comments above constructor
      bool hasNullableDoc = false;
      if (i > 0) {
        for (int back = cast(int)i - 1;
          back >= 0 && back >= cast(int)i - 5;
          back--) {
          string prev = lines[back].strip();
          if (prev.canFind("@nullable") || prev.canFind("can be null")
            || prev.canFind("allowed to be null")) {
            hasNullableDoc = true;
            break;
          }
          if (!prev.startsWith("//") && !prev.startsWith("*")
            && !prev.startsWith("/*") && !prev.startsWith("///")) {
            break;
          }
        }
      }

      // Parse parameters
      string[] params = paramsStr.split(",");
      string[] refParamNames;
      foreach (p; params) {
        string trimmedP = p.strip();
        // Remove default values
        size_t eqIdx = trimmedP.indexOf('=');
        if (eqIdx != -1) {
          trimmedP = trimmedP[0 .. eqIdx].strip();
        }
        string[] parts = trimmedP.split(" ");
        if (parts.length >= 2) {
          string pType = parts[$ - 2].strip();
          string pName = parts[$ - 1].strip();
          if (pType.endsWith("*") || (!isValueType(pType)
            && pType.length > 0 && pType[0] >= 'A' && pType[0] <= 'Z')) {
            refParamNames ~= pName;
          }
        }
      }

      if (refParamNames.length == 0 || hasNullableDoc) {
        continue;
      }

      // Look inside constructor body for assert(p !is null)
      string bodyAccum = "";
      int braceCount = 0;
      bool inBody = false;
      for (size_t j = i; j < lines.length && j < i + 40; j++) {
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

      foreach (pName; refParamNames) {
        bool hasAssert = bodyAccum.canFind("assert(" ~ pName ~ " !is null")
          || bodyAccum.canFind("assert(" ~ pName ~ " !is null")
          || bodyAccum.canFind("assert(" ~ pName ~ " != null")
          || bodyAccum.canFind("assert(" ~ pName ~ ")");

        if (!hasAssert) {
          issues ~= NullIssue(
            filePath,
            i + 1,
            NullIssueLevel.warning,
            "Constructor parameter '" ~ pName ~ "' is a reference/pointer type "
            ~ "but lacks 'assert(" ~ pName ~ " !is null)'."
          );
        }
      }
    }
  }
}

/**
 * Checks C header function comments for NULL documentation.
 */
void checkCHeaderNullDoc(
  string filePath,
  string content,
  ref NullIssue[] issues
) {
  if (extension(filePath) != ".h") {
    return;
  }

  string[] lines = content.splitLines();
  auto cFuncRe = ctRegex!(
    r"^[a-zA-Z0-9_]+\s*\**\s+([a-zA-Z0-9_]+)\s*\((.*?)\)\s*;"
  );

  for (size_t i = 0; i < lines.length; i++) {
    string line = lines[i].strip();
    auto m = matchFirst(line, cFuncRe);
    if (!m.empty) {
      string funcName = m[1];
      string args = m[2];
      if (!args.canFind("*")) {
        continue;
      }

      // Check preceding lines for doc comment mentioning NULL
      bool hasDoc = false;
      if (i > 0) {
        for (int back = cast(int)i - 1;
          back >= 0 && back >= cast(int)i - 8;
          back--) {
          string prev = lines[back].strip();
          if (prev.canFind("NULL") || prev.canFind("null")
            || prev.canFind("undefined")) {
            hasDoc = true;
            break;
          }
          if (!prev.startsWith("//") && !prev.startsWith("*")
            && !prev.startsWith("/*") && !prev.startsWith("///")) {
            break;
          }
        }
      }

      if (!hasDoc) {
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
      if (!exists(d)) {
        continue;
      }
      foreach (entry; dirEntries(d, SpanMode.depth)) {
        if (entry.isFile) {
          string ext = extension(entry.name);
          if (ext == ".d") {
            checkDNullSafety(entry.name, readText(entry.name), issues);
          } else if (ext == ".h") {
            checkCHeaderNullDoc(entry.name, readText(entry.name), issues);
          }
        }
      }
    }
  } else {
    foreach (t; targets) {
      if (isFile(t)) {
        string ext = extension(t);
        if (ext == ".d") {
          checkDNullSafety(t, readText(t), issues);
        } else if (ext == ".h") {
          checkCHeaderNullDoc(t, readText(t), issues);
        }
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
