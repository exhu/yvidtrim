/**
 * Lexer, span replacement, file collection, and reporting helpers shared by
 * the type, symbol, and module rename modes.
 */
module rename_common;

import std.json : JSONValue;
import std.path : extension;
import std.stdio : stderr, writeln;
import std.string : splitLines, startsWith;

/** Where a match was found; each mode uses a subset of these. */
enum MatchKind {
  code,
  member,
  call,
  bare,
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

/**
 * Called at each identifier start with the region (`code`, `comment`, `str`,
 * or `doc`). Must advance `i` past the consumed text.
 */
alias TokenHandler = void delegate(
  MatchKind region, size_t line, size_t lineStart, ref size_t i
);

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

/** Advances `i` past the identifier starting at `i`. */
void skipIdent(string content, ref size_t i) {
  while (i < content.length && isIdentChar(content[i])) {
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

/** Consumes a comment delimiter at `i`; returns true if one was consumed. */
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

void scanStringLit(
  string content,
  bool isDFile,
  ref size_t i,
  ref size_t line,
  ref size_t lineStart,
  scope TokenHandler onToken
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
      onToken(MatchKind.str, line, lineStart, i);
      continue;
    }
    i++;
  }
}

/** Lexes D or C source, reporting identifiers in code, comments, strings. */
void scanSource(string content, bool isDFile, scope TokenHandler onToken) {
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
        onToken(MatchKind.comment, line, lineStart, i);
      } else {
        i++;
      }
      continue;
    }
    if (c == '"' || c == '\'' || (isDFile && c == '`')) {
      scanStringLit(content, isDFile, i, line, lineStart, onToken);
      continue;
    }
    if (isIdentStart(c)) {
      onToken(MatchKind.code, line, lineStart, i);
      continue;
    }
    i++;
  }
}

/** Reports every identifier in a Markdown document as `doc`. */
void scanMarkdown(string content, scope TokenHandler onToken) {
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
      onToken(MatchKind.doc, line, lineStart, i);
      continue;
    }
    i++;
  }
}

bool isKindEnabled(MatchKind kind, bool skipComments, bool skipStrings) {
  if (kind == MatchKind.comment) {
    return !skipComments;
  }
  if (kind == MatchKind.str) {
    return !skipStrings;
  }
  return true;
}

string kindLabel(MatchKind kind) {
  if (kind == MatchKind.str) {
    return "string";
  }
  import std.conv : to;
  return kind.to!string;
}

/** Appends a Match, with its source line text, for each span. */
void addMatches(
  string file,
  string content,
  const Span[] spans,
  ref Match[] matches
) {
  auto lines = content.splitLines();
  foreach (sp; spans) {
    string lt = sp.line <= lines.length ? lines[sp.line - 1] : "";
    matches ~= Match(file, sp.line, sp.col, sp.kind, lt);
  }
}

/** Replaces every span; `spans` must be ordered and already filtered. */
string applySpans(string content, const Span[] spans, string replacement) {
  string res;
  size_t last = 0;
  foreach (sp; spans) {
    res ~= content[last .. sp.start];
    res ~= replacement;
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

JSONValue[] matchesToJson(const Match[] matches) {
  JSONValue[] arr;
  foreach (m; matches) {
    arr ~= JSONValue([
      "file": JSONValue(m.file),
      "line": JSONValue(m.line),
      "col": JSONValue(m.col),
      "kind": JSONValue(kindLabel(m.kind)),
      "text": JSONValue(m.lineText)
    ]);
  }
  return arr;
}

void printMatchLines(const Match[] matches) {
  import std.stdio : writefln;

  foreach (m; matches) {
    writefln(
      "  %s:%d:%d [%s] %s",
      m.file, m.line, m.col, kindLabel(m.kind), m.lineText
    );
  }
}

void printWarningList(string header, const string[] items) {
  if (items.length == 0) {
    return;
  }
  writeln(header);
  foreach (item; items) {
    writeln("  ", item);
  }
}

/** All git-tracked files, or an empty list (with an error) on failure. */
string[] gitTrackedFiles() {
  import std.process : execute;

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

bool isSupportedExt(string path, bool includeDocs) {
  string ext = extension(path);
  if (ext == ".d" || ext == ".c" || ext == ".h") {
    return true;
  }
  return includeDocs && ext == ".md";
}

/** Tracked (or explicitly listed) D, C, and optional Markdown files. */
string[] collectFiles(
  bool includeDocs,
  bool includeSkills,
  string[] explicitPaths
) {
  string[] result;
  string[] candidates = explicitPaths.length > 0
    ? expandPaths(explicitPaths)
    : gitTrackedFiles();
  foreach (path; candidates) {
    if (!includeSkills && path.startsWith(".agents/skills/")) {
      continue;
    }
    if (isSupportedExt(path, includeDocs)) {
      result ~= path;
    }
  }
  return result;
}

private:

string[] expandPaths(string[] paths) {
  import std.file : exists, isDir, isFile;
  import std.process : execute;

  string[] candidates;
  foreach (p; paths) {
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
  return candidates;
}
