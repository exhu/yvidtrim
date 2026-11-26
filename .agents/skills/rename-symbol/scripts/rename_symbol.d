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
  bool summaryOnly = false;
  bool findOnly = false;
  string ownerType = "";
  LineRange lines;
}

struct RenamePair {
  string oldSym;
  string newSym;
}

struct PairReport {
  string oldSym;
  string newSym;
  ScanSummary summary;
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

  if (!opts.findOnly && opts.checkCollision && !isMd) {
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

  if (opts.findOnly) {
    summary.filesChanged++;
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

void printJson(const ScanSummary summary, bool applied) {
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

void printMultiJson(
  const PairReport[] reports,
  bool findOnly,
  bool applied
) {
  import std.json : JSONValue;

  JSONValue[] results;
  foreach (rep; reports) {
    JSONValue[] mArr;
    foreach (m; rep.summary.matches) {
      mArr ~= JSONValue([
        "file": JSONValue(m.file),
        "line": JSONValue(m.line),
        "col": JSONValue(m.col),
        "kind": JSONValue(kindLabel(m.kind)),
        "text": JSONValue(m.lineText)
      ]);
    }
    results ~= JSONValue([
      "oldSymbol": JSONValue(rep.oldSym),
      "newSymbol": JSONValue(rep.newSym),
      "matchCount": JSONValue(rep.summary.matches.length),
      "filesCount": JSONValue(rep.summary.filesChanged),
      "matches": JSONValue(mArr),
      "collisions": JSONValue(rep.summary.collisions),
      "lineLengthWarnings": JSONValue(rep.summary.lengthWarnings)
    ]);
  }
  JSONValue root = [
    "mode": JSONValue(findOnly ? "find" : "batch"),
    "applied": JSONValue(applied),
    "results": JSONValue(results)
  ];
  writeln(root.toPrettyString());
}

void printPairTextReport(const PairReport rep, const Options opts) {
  if (opts.findOnly) {
    writefln(
      "Find: %d occurrence(s) across %d file(s) (%s)",
      rep.summary.matches.length, rep.summary.filesChanged, rep.oldSym
    );
  } else {
    writefln(
      "%s: %d occurrence(s) across %d file(s) (%s -> %s)",
      opts.apply ? "Applied" : "Dry-run",
      rep.summary.matches.length,
      rep.summary.filesChanged,
      rep.oldSym,
      rep.newSym
    );
  }
  if (!opts.summaryOnly) {
    foreach (m; rep.summary.matches) {
      writefln(
        "  %s:%d:%d [%s] %s",
        m.file, m.line, m.col, kindLabel(m.kind), m.lineText
      );
    }
  }
  if (rep.summary.collisions.length > 0) {
    writeln("\nWarning: NewSymbol already exists in scanned scope:");
    foreach (c; rep.summary.collisions) {
      writeln("  ", c);
    }
  }
  if (rep.summary.lengthWarnings.length > 0) {
    writeln("\nWarning: Lines exceeding 80 chars after rename:");
    foreach (w; rep.summary.lengthWarnings) {
      writeln("  ", w);
    }
  }
}

void printMultiTextReport(const PairReport[] reports, const Options opts) {
  size_t totalMatches = 0;
  size_t totalCols = 0;
  size_t totalLenWarns = 0;
  foreach (idx, rep; reports) {
    if (idx > 0) {
      writeln("");
    }
    printPairTextReport(rep, opts);
    totalMatches += rep.summary.matches.length;
    totalCols += rep.summary.collisions.length;
    totalLenWarns += rep.summary.lengthWarnings.length;
  }
  if (reports.length > 1) {
    writefln(
      "\nTotal: %d occurrence(s), %d collision(s), %d line-length warning(s).",
      totalMatches, totalCols, totalLenWarns
    );
  }
  if (!opts.findOnly && !opts.apply && totalMatches > 0) {
    writeln("\nRe-run with --apply to write changes.");
  }
}

bool parseMapSpec(string spec, ref RenamePair pair) {
  import std.string : strip;

  ptrdiff_t eq = spec.indexOf('=');
  if (eq <= 0 || eq + 1 >= spec.length) {
    stderr.writefln("Error: invalid --map spec '%s' (expected Old=New).", spec);
    return false;
  }
  pair.oldSym = spec[0 .. eq].strip();
  pair.newSym = spec[eq + 1 .. $].strip();
  if (!isValidIdentifier(pair.oldSym) || !isValidIdentifier(pair.newSym)) {
    stderr.writefln("Error: invalid identifiers in --map '%s'.", spec);
    return false;
  }
  if (pair.oldSym == pair.newSym) {
    stderr.writefln("Error: identical symbols in --map '%s'.", spec);
    return false;
  }
  return true;
}

bool loadBatchFile(string path, ref RenamePair[] pairs) {
  import std.string : strip;

  if (!exists(path) || !isFile(path)) {
    stderr.writefln("Error: batch file not found: %s", path);
    return false;
  }
  foreach (idx, rawLine; readText(path).splitLines()) {
    string line = rawLine.strip();
    if (line.length == 0 || line.startsWith("#")) {
      continue;
    }
    RenamePair p;
    if (line.indexOf('=') >= 0) {
      if (!parseMapSpec(line, p)) {
        return false;
      }
      pairs ~= p;
      continue;
    }
    string[] parts = line.split();
    if (parts.length != 2 || !isValidIdentifier(parts[0]) ||
        !isValidIdentifier(parts[1]) || parts[0] == parts[1]) {
      stderr.writefln("Error: invalid batch entry at %s:%d", path, idx + 1);
      return false;
    }
    pairs ~= RenamePair(parts[0], parts[1]);
  }
  return true;
}

bool buildPairsAndPaths(
  string[] positional,
  string[] mapSpecs,
  string batchFile,
  string[] findSyms,
  ref Options opts,
  ref RenamePair[] pairs,
  ref string[] explicitPaths
) {
  if (findSyms.length > 0) {
    if (opts.apply || mapSpecs.length > 0 || batchFile.length > 0) {
      stderr.writeln(
        "Error: --find cannot combine with --apply/--map/--batch."
      );
      return false;
    }
    opts.findOnly = true;
    foreach (sym; findSyms) {
      if (!isValidIdentifier(sym)) {
        stderr.writefln("Error: invalid --find identifier '%s'.", sym);
        return false;
      }
      pairs ~= RenamePair(sym, sym);
    }
    explicitPaths = positional;
    return true;
  }
  if (mapSpecs.length > 0 || batchFile.length > 0) {
    foreach (spec; mapSpecs) {
      RenamePair p;
      if (!parseMapSpec(spec, p)) {
        return false;
      }
      pairs ~= p;
    }
    if (batchFile.length > 0 && !loadBatchFile(batchFile, pairs)) {
      return false;
    }
    explicitPaths = positional;
    return pairs.length > 0;
  }
  if (positional.length < 2) {
    return false;
  }
  if (!isValidIdentifier(positional[0]) || !isValidIdentifier(positional[1])) {
    stderr.writeln("Error: OldSymbol and NewSymbol must be valid identifiers.");
    return false;
  }
  if (positional[0] == positional[1]) {
    stderr.writeln("Error: OldSymbol and NewSymbol are identical.");
    return false;
  }
  pairs ~= RenamePair(positional[0], positional[1]);
  explicitPaths = positional.length > 2 ? positional[2 .. $] : [];
  return true;
}

PairReport[] runRenamePairs(
  const string[] files,
  const RenamePair[] pairs,
  const Options opts
) {
  PairReport[] reports;
  foreach (pair; pairs) {
    ScanSummary summary;
    foreach (file; files) {
      processFile(file, pair.oldSym, pair.newSym, opts, summary);
    }
    reports ~= PairReport(pair.oldSym, pair.newSym, summary);
  }
  return reports;
}

int main(string[] args) {
  Options opts;
  string linesSpec;
  string[] mapSpecs;
  string batchFile;
  string[] findSyms;
  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "apply|a", "Apply changes in-place (default is dry-run)", &opts.apply,
      "lines", "Restrict to 1-based line range <start>-<end>", &linesSpec,
      "owner", "Restrict to files referencing <Type>", &opts.ownerType,
      "member-only", "Only replace .symbol or ->symbol accesses",
        &opts.memberOnly,
      "map", "Rename pair <Old>=<New> (repeatable; batch mode)", &mapSpecs,
      "batch", "File with <Old> <New> or <Old>=<New> pairs", &batchFile,
      "find", "Find occurrences without renaming (repeatable)", &findSyms,
      "summary", "Print counts and warnings only (omit match lines)",
        &opts.summaryOnly,
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

  RenamePair[] pairs;
  string[] explicitPaths;
  bool validArgs = !helpInfo.helpWanted && buildPairsAndPaths(
    args.length > 1 ? args[1 .. $] : [], mapSpecs, batchFile, findSyms,
    opts, pairs, explicitPaths
  );
  if (helpInfo.helpWanted || !validArgs) {
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

  string[] files = collectFiles(opts, explicitPaths);
  PairReport[] reports = runRenamePairs(files, pairs, opts);
  if (opts.jsonOutput) {
    if (!opts.findOnly && mapSpecs.length == 0 && batchFile.length == 0) {
      printJson(reports[0].summary, opts.apply);
    } else {
      printMultiJson(reports, opts.findOnly, opts.apply);
    }
    return 0;
  }
  printMultiTextReport(reports, opts);
  return 0;
}
