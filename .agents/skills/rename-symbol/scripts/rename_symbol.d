#!/usr/bin/env rdmd
/**
 * Renames a D/C symbol (variable, function, method, field, property,
 * constant, or enum member) with scope, owner, and member-access filters.
 */
module rename_symbol;

import std.conv : to;
import std.file : exists, isDir, isFile, readText, write;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : extension;
import std.process : execute;
import std.stdio : stderr, writefln, writeln;
import std.string : endsWith, indexOf, split, splitLines, startsWith;

enum MatchKind {
  member,
  call,
  bare,
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

struct LineRange {
  bool enabled = false;
  size_t start = 0;
  size_t end = 0;
}

struct Options {
  bool apply = false;
  bool memberOnly = false;
  bool includeDocs = false;
  bool includeSkills = false;
  bool skipComments = false;
  bool skipStrings = false;
  bool checkCollision = true;
  bool jsonOutput = false;
  string ownerType = "";
  LineRange lines;
}

struct Span {
  size_t start;
  size_t end;
  size_t line;
  size_t col;
  MatchKind kind;
}

struct ScanSummary {
  Match[] matches;
  string[] collisions;
  string[] lengthWarnings;
  size_t filesChanged;
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

bool parseLineRange(string spec, ref LineRange range) {
  if (spec.length == 0) {
    return true;
  }
  auto parts = spec.split("-");
  if (parts.length != 2) {
    return false;
  }
  try {
    range.start = parts[0].to!size_t;
    range.end = parts[1].to!size_t;
    range.enabled = true;
    return range.start >= 1 && range.end >= range.start;
  } catch (Exception) {
    return false;
  }
}

bool isSupportedExt(string path, bool includeDocs) {
  string ext = extension(path);
  if (ext == ".d" || ext == ".c" || ext == ".h") {
    return true;
  }
  return includeDocs && ext == ".md";
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

MatchKind classifyCodeIdent(string content, size_t start, size_t end) {
  size_t prev = start;
  while (prev > 0 && (content[prev - 1] == ' ' || content[prev - 1] == '\t')) {
    prev--;
  }
  if (prev > 0 && content[prev - 1] == '.') {
    return MatchKind.member;
  }
  if (prev >= 2 && content[prev - 2 .. prev] == "->") {
    return MatchKind.member;
  }
  size_t next = end;
  while (next < content.length &&
      (content[next] == ' ' || content[next] == '\t')) {
    next++;
  }
  if (next < content.length &&
      (content[next] == '(' || content[next] == '!')) {
    return MatchKind.call;
  }
  return MatchKind.bare;
}

void matchIdent(
  string content,
  string target,
  bool isComment,
  bool isStr,
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
    MatchKind kind = isComment
      ? MatchKind.comment
      : (isStr ? MatchKind.str : classifyCodeIdent(content, s, i));
    spans ~= Span(s, i, line, s - lineStart + 1, kind);
  }
}

void scanStringLit(
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
      matchIdent(content, target, false, true, line, lineStart, i, spans);
      continue;
    }
    i++;
  }
}

void scanMarkdown(string content, string target, ref Span[] spans) {
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
      size_t s = i;
      while (i < content.length && isIdentChar(content[i])) {
        i++;
      }
      if (content[s .. i] == target) {
        spans ~= Span(s, i, line, s - lineStart + 1, MatchKind.doc);
      }
      continue;
    }
    i++;
  }
}

struct LexState {
  bool inLine = false;
  bool inBlock = false;
  int nestDepth = 0;

  bool inComment() const {
    return inLine || inBlock || nestDepth > 0;
  }
}

bool advanceCommentState(
  string content,
  bool isDFile,
  ref size_t i,
  ref LexState st
) {
  char c = content[i];
  if (st.inBlock && c == '*' && i + 1 < content.length &&
      content[i + 1] == '/') {
    st.inBlock = false;
    i += 2;
    return true;
  }
  if (st.nestDepth > 0 && i + 1 < content.length) {
    if (c == '/' && content[i + 1] == '+') {
      st.nestDepth++;
      i += 2;
      return true;
    }
    if (c == '+' && content[i + 1] == '/') {
      st.nestDepth--;
      i += 2;
      return true;
    }
  }
  if (!st.inComment() && c == '/' && i + 1 < content.length) {
    if (content[i + 1] == '/') {
      st.inLine = true;
      i += 2;
      return true;
    }
    if (content[i + 1] == '*') {
      st.inBlock = true;
      i += 2;
      return true;
    }
    if (isDFile && content[i + 1] == '+') {
      st.nestDepth = 1;
      i += 2;
      return true;
    }
  }
  return false;
}

void scanCode(string content, string target, bool isDFile, ref Span[] spans) {
  size_t i = 0;
  size_t line = 1;
  size_t lineStart = 0;
  LexState st;

  while (i < content.length) {
    char c = content[i];
    if (c == '\n') {
      st.inLine = false;
      line++;
      lineStart = i + 1;
      i++;
      continue;
    }
    if (advanceCommentState(content, isDFile, i, st)) {
      continue;
    }
    if (st.inComment()) {
      if (isIdentStart(c)) {
        matchIdent(content, target, true, false, line, lineStart, i, spans);
      } else {
        i++;
      }
      continue;
    }
    if (c == '"' || c == '\'' || (isDFile && c == '`')) {
      scanStringLit(content, target, isDFile, i, line, lineStart, spans);
      continue;
    }
    if (isIdentStart(c)) {
      matchIdent(content, target, false, false, line, lineStart, i, spans);
      continue;
    }
    i++;
  }
}

bool isCodeKind(MatchKind kind) {
  return kind == MatchKind.member ||
    kind == MatchKind.call ||
    kind == MatchKind.bare;
}

bool shouldReplace(const Span sp, const Options opts) {
  if (opts.lines.enabled &&
      (sp.line < opts.lines.start || sp.line > opts.lines.end)) {
    return false;
  }
  if (opts.memberOnly && sp.kind != MatchKind.member) {
    return false;
  }
  final switch (sp.kind) {
    case MatchKind.member:
    case MatchKind.call:
    case MatchKind.bare:
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
    case MatchKind.member:
      return "member";
    case MatchKind.call:
      return "call";
    case MatchKind.bare:
      return "bare";
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
  string newSym,
  const Options opts
) {
  string res;
  size_t last = 0;
  foreach (sp; spans) {
    if (!shouldReplace(sp, opts)) {
      continue;
    }
    res ~= content[last .. sp.start];
    res ~= newSym;
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

bool hasOwnerInCode(string content, string ownerType, bool isD) {
  Span[] ownerSpans;
  scanCode(content, ownerType, isD, ownerSpans);
  foreach (os; ownerSpans) {
    if (isCodeKind(os.kind)) {
      return true;
    }
  }
  return false;
}

void collectCollisions(
  string file,
  string content,
  string newSym,
  bool isD,
  const Options opts,
  ref string[] collisions
) {
  Span[] colSpans;
  scanCode(content, newSym, isD, colSpans);
  foreach (cs; colSpans) {
    if (!isCodeKind(cs.kind)) {
      continue;
    }
    if (opts.lines.enabled &&
        (cs.line < opts.lines.start || cs.line > opts.lines.end)) {
      continue;
    }
    import std.format : format;
    collisions ~= format("%s:%d:%d", file, cs.line, cs.col);
  }
}

void processFile(
  string file,
  string oldSym,
  string newSym,
  const Options opts,
  ref ScanSummary summary
) {
  string content;
  try {
    content = readText(file);
  } catch (Exception e) {
    stderr.writefln("Warning: could not read %s: %s", file, e.msg);
    return;
  }

  bool isMd = file.endsWith(".md");
  bool isD = file.endsWith(".d");

  if (opts.ownerType.length > 0 && (isMd || !hasOwnerInCode(content,
      opts.ownerType, isD))) {
    return;
  }

  if (opts.checkCollision && !isMd) {
    collectCollisions(file, content, newSym, isD, opts, summary.collisions);
  }

  Span[] spans;
  if (isMd) {
    scanMarkdown(content, oldSym, spans);
  } else {
    scanCode(content, oldSym, isD, spans);
  }
  if (spans.length == 0) {
    return;
  }

  auto lines = content.splitLines();
  bool hasRep = false;
  foreach (sp; spans) {
    if (!shouldReplace(sp, opts)) {
      continue;
    }
    hasRep = true;
    string lt = sp.line <= lines.length ? lines[sp.line - 1] : "";
    summary.matches ~= Match(file, sp.line, sp.col, sp.kind, lt);
  }
  if (!hasRep) {
    return;
  }

  string updated = applySpans(content, spans, newSym, opts);
  if (updated != content) {
    summary.filesChanged++;
    if (newSym.length > oldSym.length) {
      summary.lengthWarnings ~= checkLineLengths(file, content, updated);
    }
    if (opts.apply) {
      write(file, updated);
    }
  }
}

void printJson(
  const ScanSummary summary,
  bool applied
) {
  import std.json : JSONValue;

  JSONValue[] mArr;
  foreach (m; summary.matches) {
    mArr ~= JSONValue([
      "file": JSONValue(m.file),
      "line": JSONValue(m.line),
      "col": JSONValue(m.col),
      "kind": JSONValue(kindLabel(m.kind)),
      "text": JSONValue(m.lineText)
    ]);
  }
  JSONValue root = [
    "applied": JSONValue(applied),
    "matchCount": JSONValue(summary.matches.length),
    "matches": JSONValue(mArr),
    "collisions": JSONValue(summary.collisions),
    "lineLengthWarnings": JSONValue(summary.lengthWarnings)
  ];
  writeln(root.toPrettyString());
}

void printTextReport(
  const ScanSummary summary,
  string oldSym,
  string newSym,
  bool applied
) {
  writefln(
    "%s: %d occurrence(s) across %d file(s) (%s -> %s)",
    applied ? "Applied" : "Dry-run",
    summary.matches.length,
    summary.filesChanged,
    oldSym,
    newSym
  );
  foreach (m; summary.matches) {
    writefln(
      "  %s:%d:%d [%s] %s",
      m.file, m.line, m.col, kindLabel(m.kind), m.lineText
    );
  }
  if (summary.collisions.length > 0) {
    writeln("\nWarning: NewSymbol already exists in scanned scope:");
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
  if (!applied && summary.matches.length > 0) {
    writeln("\nRe-run with --apply to write changes.");
  }
}

int main(string[] args) {
  Options opts;
  string linesSpec;
  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "apply|a", "Apply changes in-place (default is dry-run)", &opts.apply,
      "lines", "Restrict to 1-based line range <start>-<end>", &linesSpec,
      "owner", "Restrict to files referencing <Type>", &opts.ownerType,
      "member-only", "Only replace .symbol or ->symbol accesses",
        &opts.memberOnly,
      "include-docs", "Also scan and rename in .md files", &opts.includeDocs,
      "include-skills", "Also scan .agents/skills/ files", &opts.includeSkills,
      "skip-comments", "Do not replace inside comments", &opts.skipComments,
      "skip-strings", "Do not replace inside string/char literals",
        &opts.skipStrings,
      "check-collision", "Warn if NewSymbol already exists (default true)",
        &opts.checkCollision,
      "json", "Output results in JSON format", &opts.jsonOutput
    );
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return 2;
  }

  if (helpInfo.helpWanted || args.length < 3) {
    defaultGetoptPrinter(
      "Usage: rdmd rename_symbol.d [options] <OldSymbol> <NewSymbol> [paths]",
      helpInfo.options
    );
    return helpInfo.helpWanted ? 0 : 2;
  }

  if (!parseLineRange(linesSpec, opts.lines)) {
    stderr.writefln("Error: invalid --lines range '%s'", linesSpec);
    return 2;
  }

  string oldSym = args[1];
  string newSym = args[2];
  if (!isValidIdentifier(oldSym) || !isValidIdentifier(newSym)) {
    stderr.writeln("Error: OldSymbol and NewSymbol must be valid identifiers.");
    return 2;
  }
  if (oldSym == newSym) {
    stderr.writeln("Error: OldSymbol and NewSymbol are identical.");
    return 2;
  }

  string[] files = collectFiles(opts, args.length > 3 ? args[3 .. $] : []);
  ScanSummary summary;
  foreach (file; files) {
    processFile(file, oldSym, newSym, opts, summary);
  }

  if (opts.jsonOutput) {
    printJson(summary, opts.apply);
    return 0;
  }
  printTextReport(summary, oldSym, newSym, opts.apply);
  return 0;
}
