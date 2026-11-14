#!/usr/bin/env rdmd
/**
 * Renames or moves a D module (e.g. a.b.c -> a.b.internal.c), updating
 * module declarations, imports, qualified references, file paths, and
 * meson.build source lists.
 */
module rename_module;

import std.file : exists, mkdirRecurse, readText, rename, write;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : baseName, dirName, extension;
import std.process : execute;
import std.stdio : stderr, writefln, writeln;
import std.string : endsWith, indexOf, replace, split, splitLines, startsWith;

enum MatchKind {
  code,
  comment,
  str,
  doc,
  meson
}

struct Match {
  string file;
  size_t line;
  size_t col;
  MatchKind kind;
  string lineText;
}

struct Span {
  size_t start;
  size_t end;
  size_t line;
  size_t col;
  MatchKind kind;
}

struct Options {
  bool apply = false;
  bool noMove = false;
  bool asPackage = false;
  bool includeDocs = false;
  bool includeSkills = false;
  bool skipComments = false;
  bool skipStrings = false;
  bool jsonOutput = false;
}

struct MovePlan {
  bool found = false;
  string srcFile;
  string dstFile;
  string srcRel;
  string dstRel;
  string mesonDir;
  bool isPackage = false;
  bool collision = false;
}

struct ScanSummary {
  MovePlan movePlan;
  Match[] matches;
  string[] lengthWarnings;
  size_t filesChanged;
}

bool isIdentStart(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

bool isIdentChar(char c) {
  return isIdentStart(c) || (c >= '0' && c <= '9');
}

bool isValidModuleName(string modName) {
  if (modName.length == 0) {
    return false;
  }
  auto parts = modName.split(".");
  foreach (p; parts) {
    if (p.length == 0 || !isIdentStart(p[0])) {
      return false;
    }
    foreach (c; p[1 .. $]) {
      if (!isIdentChar(c)) {
        return false;
      }
    }
  }
  return true;
}

bool hasUpperCase(string s) {
  foreach (c; s) {
    if (c >= 'A' && c <= 'Z') {
      return true;
    }
  }
  return false;
}

string[] gitTrackedFiles() {
  auto res = execute(["git", "ls-files"]);
  if (res.status != 0) {
    stderr.writeln("Error running git ls-files: ", res.output);
    return [];
  }
  string[] files;
  foreach (line; res.output.splitLines()) {
    if (line.length > 0) {
      files ~= line;
    }
  }
  return files;
}

MovePlan resolveMovePlan(
  string oldMod,
  string newMod,
  const string[] tracked,
  bool asPackage
) {
  MovePlan plan;
  string oldSlash = oldMod.replace(".", "/");
  string newSlash = newMod.replace(".", "/");
  string[] roots = ["", "yguilib/"];

  foreach (r; roots) {
    string candMod = r ~ "source/" ~ oldSlash ~ ".d";
    string candPkg = r ~ "source/" ~ oldSlash ~ "/package.d";
    foreach (f; tracked) {
      if (f == candMod || f == candPkg) {
        plan.found = true;
        plan.srcFile = f;
        plan.isPackage = (f == candPkg) || asPackage;
        plan.mesonDir = r;
        plan.srcRel = f[r.length .. $];
        string tail = plan.isPackage
          ? "source/" ~ newSlash ~ "/package.d"
          : "source/" ~ newSlash ~ ".d";
        plan.dstRel = tail;
        plan.dstFile = r ~ tail;
        plan.collision = exists(plan.dstFile);
        return plan;
      }
    }
  }
  return plan;
}

void matchDotted(
  string content,
  string target,
  MatchKind kind,
  size_t line,
  size_t lineStart,
  ref size_t i,
  ref Span[] spans
) {
  size_t s = i;
  while (i < content.length) {
    while (i < content.length && isIdentChar(content[i])) {
      i++;
    }
    if (i + 1 < content.length && content[i] == '.' &&
        isIdentStart(content[i + 1])) {
      i++;
      continue;
    }
    break;
  }
  string tok = content[s .. i];
  if (tok == target || tok.startsWith(target ~ ".")) {
    size_t end = s + target.length;
    spans ~= Span(s, end, line, s - lineStart + 1, kind);
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

bool advanceComment(string content, ref size_t i, ref LexState st) {
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
    if (content[i + 1] == '+') {
      st.nestDepth = 1;
      i += 2;
      return true;
    }
  }
  return false;
}

void scanDString(
  string content,
  string target,
  ref size_t i,
  ref size_t line,
  ref size_t lineStart,
  ref Span[] spans
) {
  char quote = content[i];
  bool raw = (quote == '`') || (quote == '"' && i > 0 && content[i - 1] == 'r');
  i++;
  while (i < content.length) {
    char sc = content[i];
    if (sc == '\n') {
      line++;
      lineStart = i + 1;
      i++;
      if (quote == '\'') {
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
      matchDotted(content, target, MatchKind.str, line, lineStart, i, spans);
      continue;
    }
    i++;
  }
}

void scanDCode(string content, string target, ref Span[] spans) {
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
    if (advanceComment(content, i, st)) {
      continue;
    }
    if (st.inComment()) {
      if (isIdentStart(c)) {
        matchDotted(
          content, target, MatchKind.comment, line, lineStart, i, spans
        );
      } else {
        i++;
      }
      continue;
    }
    if (c == '"' || c == '\'' || c == '`') {
      scanDString(content, target, i, line, lineStart, spans);
      continue;
    }
    if (isIdentStart(c)) {
      matchDotted(content, target, MatchKind.code, line, lineStart, i, spans);
      continue;
    }
    i++;
  }
}

void scanMarkdown(string content, string target, ref Span[] spans) {
  size_t i = 0;
  size_t line = 1;
  size_t lineStart = 0;
  while (i < content.length) {
    if (content[i] == '\n') {
      line++;
      lineStart = i + 1;
      i++;
      continue;
    }
    if (isIdentStart(content[i])) {
      matchDotted(content, target, MatchKind.doc, line, lineStart, i, spans);
      continue;
    }
    i++;
  }
}

bool shouldReplace(MatchKind kind, const Options opts) {
  final switch (kind) {
    case MatchKind.code:
    case MatchKind.doc:
    case MatchKind.meson:
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
    case MatchKind.meson:
      return "meson";
  }
}

string applySpans(
  string content,
  const Span[] spans,
  string newMod,
  const Options opts
) {
  string res;
  size_t last = 0;
  foreach (sp; spans) {
    if (!shouldReplace(sp.kind, opts)) {
      continue;
    }
    res ~= content[last .. sp.start];
    res ~= newMod;
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

void processTextFile(
  string file,
  string oldMod,
  string newMod,
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

  Span[] spans;
  if (file.endsWith(".md")) {
    scanMarkdown(content, oldMod, spans);
  } else {
    scanDCode(content, oldMod, spans);
  }
  if (spans.length == 0) {
    return;
  }

  auto lines = content.splitLines();
  bool hasRep = false;
  foreach (sp; spans) {
    if (!shouldReplace(sp.kind, opts)) {
      continue;
    }
    hasRep = true;
    string lt = sp.line <= lines.length ? lines[sp.line - 1] : "";
    summary.matches ~= Match(file, sp.line, sp.col, sp.kind, lt);
  }
  if (!hasRep) {
    return;
  }

  string updated = applySpans(content, spans, newMod, opts);
  if (updated != content) {
    summary.filesChanged++;
    if (newMod.length > oldMod.length) {
      summary.lengthWarnings ~= checkLineLengths(file, content, updated);
    }
    if (opts.apply) {
      write(file, updated);
    }
  }
}

void processMesonFile(
  string file,
  const MovePlan plan,
  const Options opts,
  ref ScanSummary summary
) {
  string content;
  try {
    content = readText(file);
  } catch (Exception) {
    return;
  }

  string needle = "'" ~ plan.srcRel ~ "'";
  if (content.indexOf(needle) < 0) {
    return;
  }

  auto lines = content.splitLines();
  foreach (idx, l; lines) {
    ptrdiff_t col = l.indexOf(needle);
    if (col >= 0) {
      summary.matches ~= Match(
        file, idx + 1, cast(size_t)col + 1, MatchKind.meson, l
      );
    }
  }

  string repl = "'" ~ plan.dstRel ~ "'";
  string updated = content.replace(needle, repl);
  if (updated != content) {
    summary.filesChanged++;
    if (opts.apply) {
      write(file, updated);
    }
  }
}

bool executeFileMove(const MovePlan plan) {
  string dstDir = dirName(plan.dstFile);
  if (!exists(dstDir)) {
    mkdirRecurse(dstDir);
  }
  auto res = execute(["git", "mv", plan.srcFile, plan.dstFile]);
  if (res.status == 0) {
    return true;
  }
  try {
    rename(plan.srcFile, plan.dstFile);
    return true;
  } catch (Exception e) {
    stderr.writefln("Error moving %s: %s", plan.srcFile, e.msg);
    return false;
  }
}

void printJson(const ScanSummary summary, bool applied, bool noMove) {
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
  JSONValue moveObj = [
    "found": JSONValue(summary.movePlan.found),
    "willMove": JSONValue(summary.movePlan.found && !noMove),
    "srcFile": JSONValue(summary.movePlan.srcFile),
    "dstFile": JSONValue(summary.movePlan.dstFile),
    "collision": JSONValue(summary.movePlan.collision)
  ];
  JSONValue root = [
    "applied": JSONValue(applied),
    "move": moveObj,
    "matchCount": JSONValue(summary.matches.length),
    "matches": JSONValue(mArr),
    "lineLengthWarnings": JSONValue(summary.lengthWarnings)
  ];
  writeln(root.toPrettyString());
}

void printTextReport(
  const ScanSummary summary,
  string oldMod,
  string newMod,
  bool applied,
  bool noMove
) {
  writefln(
    "%s: %d occurrence(s) across %d file(s) (%s -> %s)",
    applied ? "Applied" : "Dry-run",
    summary.matches.length,
    summary.filesChanged,
    oldMod,
    newMod
  );
  if (summary.movePlan.found && !noMove) {
    writefln(
      "  [file] %s -> %s",
      summary.movePlan.srcFile,
      summary.movePlan.dstFile
    );
  } else if (!summary.movePlan.found) {
    writeln("  [file] No matching .d file found on disk for ", oldMod);
  }
  foreach (m; summary.matches) {
    writefln(
      "  %s:%d:%d [%s] %s",
      m.file, m.line, m.col, kindLabel(m.kind), m.lineText
    );
  }
  if (summary.movePlan.collision) {
    writefln("\nError: target file already exists: %s",
      summary.movePlan.dstFile);
  }
  if (summary.lengthWarnings.length > 0) {
    writeln("\nWarning: Lines exceeding 80 chars after rename:");
    foreach (w; summary.lengthWarnings) {
      writeln("  ", w);
    }
  }
  if (!applied && (summary.matches.length > 0 || summary.movePlan.found)) {
    writeln("\nRe-run with --apply to write changes.");
  }
}

int main(string[] args) {
  Options opts;
  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "apply|a", "Apply edits and move file (default is dry-run)", &opts.apply,
      "no-move", "Update code only; do not move .d file or edit meson.build",
        &opts.noMove,
      "as-package", "Map NewModule to <path>/package.d", &opts.asPackage,
      "include-docs", "Also scan and rename in .md files", &opts.includeDocs,
      "include-skills", "Also scan .agents/skills/ files", &opts.includeSkills,
      "skip-comments", "Do not replace inside comments", &opts.skipComments,
      "skip-strings", "Do not replace inside string/char literals",
        &opts.skipStrings,
      "json", "Output results in JSON format", &opts.jsonOutput
    );
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return 2;
  }

  if (helpInfo.helpWanted || args.length < 3) {
    defaultGetoptPrinter(
      "Usage: rdmd rename_module.d [options] <OldModule> <NewModule>",
      helpInfo.options
    );
    return helpInfo.helpWanted ? 0 : 2;
  }

  string oldMod = args[1];
  string newMod = args[2];
  if (!isValidModuleName(oldMod) || !isValidModuleName(newMod)) {
    stderr.writeln("Error: OldModule and NewModule must be valid D modules.");
    return 2;
  }
  if (oldMod == newMod) {
    stderr.writeln("Error: OldModule and NewModule are identical.");
    return 2;
  }
  if (hasUpperCase(newMod)) {
    stderr.writeln("Warning: codestyle.md requires lowercase module names.");
  }

  string[] tracked = gitTrackedFiles();
  ScanSummary summary;
  summary.movePlan = resolveMovePlan(oldMod, newMod, tracked, opts.asPackage);

  if (opts.apply && summary.movePlan.found && !opts.noMove &&
      summary.movePlan.collision) {
    stderr.writefln("Error: target file exists: %s",
      summary.movePlan.dstFile);
    return 1;
  }

  foreach (f; tracked) {
    if (!opts.includeSkills && f.startsWith(".agents/skills/")) {
      continue;
    }
    if (f.endsWith(".d") || (opts.includeDocs && f.endsWith(".md"))) {
      processTextFile(f, oldMod, newMod, opts, summary);
    } else if (!opts.noMove && summary.movePlan.found &&
        baseName(f) == "meson.build") {
      string expectedMeson = summary.movePlan.mesonDir ~ "meson.build";
      if (f == expectedMeson) {
        processMesonFile(f, summary.movePlan, opts, summary);
      }
    }
  }

  if (opts.apply && summary.movePlan.found && !opts.noMove) {
    if (!executeFileMove(summary.movePlan)) {
      return 1;
    }
  }

  if (opts.jsonOutput) {
    printJson(summary, opts.apply, opts.noMove);
    return 0;
  }
  printTextReport(summary, oldMod, newMod, opts.apply, opts.noMove);
  return 0;
}
