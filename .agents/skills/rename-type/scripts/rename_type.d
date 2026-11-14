#!/usr/bin/env rdmd
/**
 * Renames a type identifier across D, C, and optional Markdown files.
 */
module rename_type;

import std.file : exists, isDir, isFile, readText, write;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : extension;
import std.process : execute;
import std.stdio : stderr, writefln, writeln;
import std.string : endsWith, indexOf, splitLines, startsWith;

enum MatchKind {
  code,
  comment,
  str,
  doc
}

struct Match {
  string file;
  size_t line;
  size_t col;
  MatchKind kind;
  string lineText;
}

struct Options {
  bool apply = false;
  bool includeDocs = false;
  bool includeSkills = false;
  bool skipComments = false;
  bool skipStrings = false;
  bool checkCollision = true;
  bool jsonOutput = false;
}

bool isIdentStart(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

bool isIdentChar(char c) {
  return isIdentStart(c) || (c >= '0' && c <= '9');
}

bool isValidIdentifier(string s) {
  if (s.length == 0 || !isIdentStart(s[0])) {
    return false;
  }
  foreach (c; s[1 .. $]) {
    if (!isIdentChar(c)) {
      return false;
    }
  }
  return true;
}

string toSnakeCase(string name) {
  string res;
  foreach (i, char c; name) {
    if (c >= 'A' && c <= 'Z') {
      if (i > 0 && name[i - 1] >= 'a' && name[i - 1] <= 'z') {
        res ~= '_';
      }
      res ~= cast(char)(c + ('a' - 'A'));
    } else {
      res ~= c;
    }
  }
  return res;
}

bool isSupportedExt(string path, bool includeDocs) {
  string ext = extension(path);
  if (ext == ".d" || ext == ".c" || ext == ".h") {
    return true;
  }
  if (includeDocs && ext == ".md") {
    return true;
  }
  return false;
}

string[] collectFiles(const Options opts, string[] explicitPaths) {
  string[] candidates;
  if (explicitPaths.length > 0) {
    foreach (p; explicitPaths) {
      if (!exists(p)) {
        stderr.writefln("Warning: path not found: %s", p);
        continue;
      }
      if (isDir(p)) {
        auto res = execute(["git", "ls-files", "--", p]);
        if (res.status == 0) {
          foreach (line; res.output.splitLines()) {
            if (line.length > 0) {
              candidates ~= line;
            }
          }
        }
      } else if (isFile(p)) {
        candidates ~= p;
      }
    }
  } else {
    auto res = execute(["git", "ls-files"]);
    if (res.status != 0) {
      stderr.writeln("Error running git ls-files: ", res.output);
      return [];
    }
    foreach (line; res.output.splitLines()) {
      if (line.length > 0) {
        candidates ~= line;
      }
    }
  }

  string[] result;
  foreach (path; candidates) {
    if (!opts.includeSkills && path.startsWith(".agents/skills/")) {
      continue;
    }
    if (isSupportedExt(path, opts.includeDocs)) {
      result ~= path;
    }
  }
  return result;
}

struct Span {
  size_t start;
  size_t end;
  size_t line;
  size_t col;
  MatchKind kind;
}

void scanMarkdown(
  string content,
  string target,
  ref Span[] spans
) {
  size_t line = 1;
  size_t lineStart = 0;
  size_t i = 0;
  while (i < content.length) {
    if (content[i] == '\n') {
      line++;
      lineStart = i + 1;
      i++;
      continue;
    }
    if (isIdentStart(content[i])) {
      size_t start = i;
      while (i < content.length && isIdentChar(content[i])) {
        i++;
      }
      if (content[start .. i] == target) {
        spans ~= Span(start, i, line, start - lineStart + 1, MatchKind.doc);
      }
      continue;
    }
    i++;
  }
}

void matchIdentInScan(
  string content,
  string target,
  MatchKind kind,
  size_t line,
  size_t lineStart,
  ref size_t i,
  ref Span[] spans
) {
  size_t s = i;
  while (i < content.length && isIdentChar(content[i])) {
    i++;
  }
  if (content[s .. i] == target) {
    spans ~= Span(s, i, line, s - lineStart + 1, kind);
  }
}

void scanStringLiteral(
  string content,
  string target,
  bool isDFile,
  ref size_t i,
  ref size_t line,
  ref size_t lineStart,
  ref Span[] spans
) {
  char quote = content[i];
  bool raw = (quote == '`');
  if (isDFile && quote == '"' && i > 0 && content[i - 1] == 'r') {
    raw = true;
  }
  i++;
  while (i < content.length) {
    char sc = content[i];
    if (sc == '\n') {
      line++;
      lineStart = i + 1;
      i++;
      if (quote == '\'' || (!isDFile && quote == '"')) {
        break;
      }
      continue;
    }
    if (!raw && sc == '\\' && i + 1 < content.length) {
      i += 2;
      continue;
    }
    if (sc == quote) {
      i++;
      break;
    }
    if (isIdentStart(sc)) {
      matchIdentInScan(
        content, target, MatchKind.str, line, lineStart, i, spans
      );
      continue;
    }
    i++;
  }
}

void scanCode(
  string content,
  string target,
  bool isDFile,
  ref Span[] spans
) {
  size_t i = 0;
  size_t line = 1;
  size_t lineStart = 0;
  bool inLineComment = false;
  bool inBlockComment = false;
  int nestDepth = 0;

  while (i < content.length) {
    char c = content[i];
    if (c == '\n') {
      inLineComment = false;
      line++;
      lineStart = i + 1;
      i++;
      continue;
    }
    if (inBlockComment && c == '*' && i + 1 < content.length &&
        content[i + 1] == '/') {
      inBlockComment = false;
      i += 2;
      continue;
    }
    if (nestDepth > 0 && i + 1 < content.length) {
      if (c == '/' && content[i + 1] == '+') {
        nestDepth++;
        i += 2;
        continue;
      }
      if (c == '+' && content[i + 1] == '/') {
        nestDepth--;
        i += 2;
        continue;
      }
    }
    if (inLineComment || inBlockComment || nestDepth > 0) {
      if (isIdentStart(c)) {
        matchIdentInScan(
          content, target, MatchKind.comment, line, lineStart, i, spans
        );
      } else {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < content.length) {
      if (content[i + 1] == '/') {
        inLineComment = true;
        i += 2;
        continue;
      }
      if (content[i + 1] == '*') {
        inBlockComment = true;
        i += 2;
        continue;
      }
      if (isDFile && content[i + 1] == '+') {
        nestDepth = 1;
        i += 2;
        continue;
      }
    }
    if (c == '"' || c == '\'' || (isDFile && c == '`')) {
      scanStringLiteral(content, target, isDFile, i, line, lineStart, spans);
      continue;
    }
    if (isIdentStart(c)) {
      matchIdentInScan(
        content, target, MatchKind.code, line, lineStart, i, spans
      );
      continue;
    }
    i++;
  }
}

bool shouldReplace(MatchKind kind, const Options opts) {
  final switch (kind) {
    case MatchKind.code:
    case MatchKind.doc:
      return true;
    case MatchKind.comment:
      return !opts.skipComments;
    case MatchKind.str:
      return !opts.skipStrings;
  }
}

string kindLabel(MatchKind kind) {
  final switch (kind) {
    case MatchKind.code:
      return "code";
    case MatchKind.comment:
      return "comment";
    case MatchKind.str:
      return "string";
    case MatchKind.doc:
      return "doc";
  }
}

string applySpans(
  string content,
  const Span[] spans,
  string newType,
  const Options opts
) {
  if (spans.length == 0) {
    return content;
  }
  string res;
  size_t last = 0;
  foreach (sp; spans) {
    if (!shouldReplace(sp.kind, opts)) {
      continue;
    }
    res ~= content[last .. sp.start];
    res ~= newType;
    last = sp.end;
  }
  res ~= content[last .. $];
  return res;
}

string[] checkLineLengths(string file, string original, string updated) {
  string[] warnings;
  auto origLines = original.splitLines();
  auto newLines = updated.splitLines();
  foreach (idx, l; newLines) {
    bool changed = idx >= origLines.length || l != origLines[idx];
    if (changed && l.length > 80) {
      import std.format : format;
      warnings ~= format("%s:%d: length %d > 80", file, idx + 1, l.length);
    }
  }
  return warnings;
}

void printJson(
  const Match[] matches,
  const string[] collisions,
  const string[] lengthWarnings,
  const string[] fileHints,
  bool applied
) {
  import std.json : JSONValue;

  JSONValue[] mArr;
  foreach (m; matches) {
    JSONValue obj = [
      "file": JSONValue(m.file),
      "line": JSONValue(m.line),
      "col": JSONValue(m.col),
      "kind": JSONValue(kindLabel(m.kind)),
      "text": JSONValue(m.lineText)
    ];
    mArr ~= obj;
  }
  JSONValue root = [
    "applied": JSONValue(applied),
    "matchCount": JSONValue(matches.length),
    "matches": JSONValue(mArr),
    "collisions": JSONValue(collisions),
    "lineLengthWarnings": JSONValue(lengthWarnings),
    "fileHints": JSONValue(fileHints)
  ];
  writeln(root.toPrettyString());
}

struct ScanSummary {
  Match[] matches;
  string[] collisions;
  string[] lengthWarnings;
  string[] fileHints;
  size_t filesChanged;
}

void processFile(
  string file,
  string oldType,
  string newType,
  string oldSnake,
  const Options opts,
  ref ScanSummary summary
) {
  if (file.indexOf(oldSnake) >= 0) {
    summary.fileHints ~= file;
  }

  string content;
  try {
    content = readText(file);
  } catch (Exception e) {
    stderr.writefln("Warning: could not read %s: %s", file, e.msg);
    return;
  }

  bool isMd = file.endsWith(".md");
  bool isD = file.endsWith(".d");

  if (opts.checkCollision && !isMd) {
    Span[] colSpans;
    scanCode(content, newType, isD, colSpans);
    foreach (cs; colSpans) {
      if (cs.kind == MatchKind.code) {
        import std.format : format;
        summary.collisions ~= format("%s:%d:%d", file, cs.line, cs.col);
      }
    }
  }

  Span[] spans;
  if (isMd) {
    scanMarkdown(content, oldType, spans);
  } else {
    scanCode(content, oldType, isD, spans);
  }
  if (spans.length == 0) {
    return;
  }

  auto lines = content.splitLines();
  bool fileHasReplacement = false;
  foreach (sp; spans) {
    if (!shouldReplace(sp.kind, opts)) {
      continue;
    }
    fileHasReplacement = true;
    string lt = sp.line <= lines.length ? lines[sp.line - 1] : "";
    summary.matches ~= Match(file, sp.line, sp.col, sp.kind, lt);
  }
  if (!fileHasReplacement) {
    return;
  }

  string updated = applySpans(content, spans, newType, opts);
  if (updated != content) {
    summary.filesChanged++;
    if (newType.length > oldType.length) {
      summary.lengthWarnings ~= checkLineLengths(file, content, updated);
    }
    if (opts.apply) {
      write(file, updated);
    }
  }
}

void printTextReport(
  const ScanSummary summary,
  string oldType,
  string newType,
  bool applied
) {
  writefln(
    "%s: %d occurrence(s) across %d file(s) (%s -> %s)",
    applied ? "Applied" : "Dry-run",
    summary.matches.length,
    summary.filesChanged,
    oldType,
    newType
  );
  foreach (m; summary.matches) {
    writefln(
      "  %s:%d:%d [%s] %s",
      m.file, m.line, m.col, kindLabel(m.kind), m.lineText
    );
  }
  if (summary.collisions.length > 0) {
    writeln("\nWarning: NewType already exists in code:");
    foreach (c; summary.collisions) {
      writeln("  ", c);
    }
  }
  if (summary.lengthWarnings.length > 0) {
    writeln("\nWarning: Lines exceeding 80 chars after rename:");
    foreach (w; summary.lengthWarnings) {
      writeln("  ", w);
    }
  }
  if (summary.fileHints.length > 0) {
    writeln("\nNote: Filenames matching snake_case of OldType:");
    foreach (h; summary.fileHints) {
      writeln("  ", h);
    }
  }
  if (!applied && summary.matches.length > 0) {
    writeln("\nRe-run with --apply to write changes.");
  }
}

int main(string[] args) {
  Options opts;
  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "apply|a", "Apply changes in-place (default is dry-run)", &opts.apply,
      "include-docs", "Also scan and rename in .md files", &opts.includeDocs,
      "include-skills", "Also scan .agents/skills/ files", &opts.includeSkills,
      "skip-comments", "Do not replace inside comments", &opts.skipComments,
      "skip-strings", "Do not replace inside string/char literals",
        &opts.skipStrings,
      "check-collision", "Warn if NewType already exists (default true)",
        &opts.checkCollision,
      "json", "Output results in JSON format", &opts.jsonOutput
    );
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return 2;
  }

  if (helpInfo.helpWanted || args.length < 3) {
    defaultGetoptPrinter(
      "Usage: rdmd rename_type.d [options] <OldType> <NewType> [paths...]",
      helpInfo.options
    );
    return helpInfo.helpWanted ? 0 : 2;
  }

  string oldType = args[1];
  string newType = args[2];
  if (!isValidIdentifier(oldType) || !isValidIdentifier(newType)) {
    stderr.writeln("Error: OldType and NewType must be valid identifiers.");
    return 2;
  }
  if (oldType == newType) {
    stderr.writeln("Error: OldType and NewType are identical.");
    return 2;
  }

  string[] explicitPaths = args.length > 3 ? args[3 .. $] : [];
  string[] files = collectFiles(opts, explicitPaths);
  string oldSnake = toSnakeCase(oldType);

  ScanSummary summary;
  foreach (file; files) {
    processFile(file, oldType, newType, oldSnake, opts, summary);
  }

  if (opts.jsonOutput) {
    printJson(
      summary.matches,
      summary.collisions,
      summary.lengthWarnings,
      summary.fileHints,
      opts.apply
    );
    return 0;
  }

  printTextReport(summary, oldType, newType, opts.apply);
  return 0;
}
