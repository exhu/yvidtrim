#!/usr/bin/env rdmd
/**
 * Code style checker for D and C files in yvidtrim.
 * Enforces codestyle.md:
 *  - 2-space indent, no tabs
 *  - Opening brace on the same line
 *  - Lowercase file names
 *  - Section visibility order (public: -> protected: -> private:)
 *  - No inline visibility keywords (e.g. 'private void foo()')
 *  - Scoped imports for heavy Phobos modules
 *  - Function length <= 50 lines
 *  - D: no default parameter values, no 'out' parameters,
 *    no overloaded functions, no consecutive capital letters in symbol names,
 *    and constructor count / <= 3 parameter constraints
 *  - D: override HandleResult handleEvent calls super.handleEvent
 *  - D: classes that call startTimer also call stopTimer
 */
module check_style;

import core.sys.posix.sys.stat : fstat, stat_t, S_ISFIFO, S_ISREG;
import std.algorithm : canFind, countUntil;
import std.ascii : isAlpha, isAlphaNum, isUpper, isWhite;
import std.conv : to;
import std.file : dirEntries, exists, isDir, isFile, readText, SpanMode;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : baseName, extension;
import std.process : execute;
import std.regex : ctRegex, matchFirst;
import std.stdio : stderr, stdin, writeln, writefln;
import std.string : endsWith, indexOf, isNumeric, splitLines, startsWith,
  strip;

enum IssueLevel {
  warning,
  error
}

struct Issue {
  string file;
  size_t line;
  size_t col;
  IssueLevel level;
  string message;
}

struct FileSpan {
  string file;
  size_t startLine;
  size_t lineCount;
}

bool isStdinPiped() {
  stat_t st;
  if (fstat(0, &st) == 0) {
    return (S_ISFIFO(st.st_mode) || S_ISREG(st.st_mode)) != 0;
  }
  return false;
}

bool isTrackedInGit(string path) {
  auto res = execute(["git", "ls-files", "--error-unmatch", "--", path]);
  return res.status == 0;
}

FileSpan[] parseGitDiffUnified(string diffText) {
  FileSpan[] spans;
  string currentFile = null;

  foreach (line; diffText.splitLines()) {
    if (line.startsWith("+++ b/")) {
      currentFile = line[6 .. $];
    } else if (line.startsWith("@@ ") && currentFile !is null) {
      size_t plusIdx = line.indexOf('+');
      if (plusIdx == -1) {
        continue;
      }
      size_t spaceIdx = line.indexOf(' ', plusIdx);
      if (spaceIdx == -1) {
        continue;
      }
      string hunk = line[plusIdx + 1 .. spaceIdx];
      size_t commaIdx = hunk.indexOf(',');
      size_t startLine = 0;
      size_t lineCount = 1;
      if (commaIdx != -1) {
        startLine = to!size_t(hunk[0 .. commaIdx]);
        lineCount = to!size_t(hunk[commaIdx + 1 .. $]);
      } else {
        startLine = to!size_t(hunk);
      }
      spans ~= FileSpan(currentFile, startLine, lineCount);
    }
  }
  return spans;
}

bool isSourceFile(string path) {
  string ext = extension(path);
  return ext == ".d" || ext == ".c" || ext == ".h";
}

bool hasUppercase(string name) {
  foreach (dchar c; name) {
    if (c >= 'A' && c <= 'Z') {
      return true;
    }
  }
  return false;
}

/**
 * Checks if a line is within git diff spans for the file.
 */
bool isLineInSpans(size_t lineNo, const FileSpan[] spans) {
  if (spans.length == 0) {
    return true;
  }
  foreach (const ref span; spans) {
    if (lineNo >= span.startLine && lineNo < span.startLine + span.lineCount) {
      return true;
    }
  }
  return false;
}

struct ScopeState {
  bool isTypeScope;
  bool isConditional;
  size_t ctorCount;
  size_t[string] funcs;
}

bool hasConsecutiveCaps(string name) {
  if (name.canFind('_')) {
    return false;
  }
  bool prevUpper = false;
  foreach (char c; name) {
    if (isUpper(c)) {
      if (prevUpper) {
        return true;
      }
      prevUpper = true;
    } else {
      prevUpper = false;
    }
  }
  return false;
}

bool isControlOrKeyword(string name) {
  switch (name) {
    case "if":
    case "else":
    case "while":
    case "for":
    case "foreach":
    case "foreach_reverse":
    case "switch":
    case "catch":
    case "assert":
    case "return":
    case "throw":
    case "mixin":
    case "pragma":
    case "version":
    case "debug":
    case "synchronized":
    case "with":
    case "scope":
    case "invariant":
    case "unittest":
    case "sizeof":
    case "typeof":
    case "cast":
    case "new":
    case "delete":
    case "extern":
    case "align":
    case "deprecated":
    case "inout":
    case "import":
    case "package":
    case "const":
    case "immutable":
    case "shared":
      return true;
    default:
      return false;
  }
}

bool isOverloadExempt(string name) {
  return name == "visit" || name.startsWith("op") || name.startsWith("~");
}

struct ParamListInfo {
  bool hasDefault;
  bool hasOutParam;
  size_t paramCount;
}

struct ParenContentResult {
  string content;
  size_t endIdx;
}

bool isParamStorageClass(string token) {
  switch (token) {
    case "scope":
    case "return":
    case "lazy":
    case "in":
    case "ref":
    case "auto":
    case "const":
    case "immutable":
    case "shared":
    case "inout":
    case "final":
      return true;
    default:
      return false;
  }
}

bool paramHasOutKeyword(string param) {
  size_t i = 0;
  while (i < param.length) {
    while (i < param.length && isWhite(param[i])) {
      i++;
    }
    if (i >= param.length) {
      return false;
    }
    if (param[i] == '@') {
      i++;
      while (i < param.length && (isAlphaNum(param[i]) || param[i] == '_')) {
        i++;
      }
      if (i < param.length && param[i] == '(') {
        int depth = 1;
        i++;
        while (i < param.length && depth > 0) {
          if (param[i] == '(') {
            depth++;
          } else if (param[i] == ')') {
            depth--;
          }
          i++;
        }
      }
      continue;
    }
    if (!(isAlpha(param[i]) || param[i] == '_')) {
      return false;
    }
    size_t start = i;
    while (i < param.length && (isAlphaNum(param[i]) || param[i] == '_')) {
      i++;
    }
    string token = param[start .. i];
    if (token == "out") {
      return true;
    }
    if (!isParamStorageClass(token)) {
      return false;
    }
  }
  return false;
}

ParamListInfo inspectParamList(string paramStr) {
  ParamListInfo info;
  string inner = paramStr.strip();
  if (inner.length == 0) {
    return info;
  }

  int depth = 0;
  bool inStr = false;
  char quote = 0;
  size_t commas = 0;
  size_t paramStart = 0;

  for (size_t i = 0; i < inner.length; i++) {
    char c = inner[i];
    if (inStr) {
      if (c == '\\' && i + 1 < inner.length) {
        i++;
      } else if (c == quote) {
        inStr = false;
      }
      continue;
    }
    if (c == '"' || c == '\'' || c == '`') {
      inStr = true;
      quote = c;
    } else if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      if (depth > 0) {
        depth--;
      }
    } else if (depth == 0 && c == ',') {
      if (paramHasOutKeyword(inner[paramStart .. i])) {
        info.hasOutParam = true;
      }
      paramStart = i + 1;
      commas++;
    } else if (depth == 0 && c == '=') {
      char prev = i > 0 ? inner[i - 1] : 0;
      char next = i + 1 < inner.length ? inner[i + 1] : 0;
      if (prev != '=' && prev != '!' && prev != '<' && prev != '>'
        && next != '=' && next != '>') {
        info.hasDefault = true;
      }
    }
  }
  if (paramHasOutKeyword(inner[paramStart .. $])) {
    info.hasOutParam = true;
  }
  info.paramCount = commas + 1;
  return info;
}

ParenContentResult extractParenContent(
  const string[] lines,
  size_t startIdx,
  size_t openCol
) {
  string acc = "";
  int depth = 0;
  bool inStr = false;
  char quote = 0;
  size_t endIdx = startIdx;

  for (size_t li = startIdx; li < lines.length; li++) {
    string ln = lines[li];
    size_t colStart = (li == startIdx) ? openCol : 0;
    for (size_t ci = colStart; ci < ln.length; ci++) {
      char c = ln[ci];
      if (inStr) {
        acc ~= c;
        if (c == '\\' && ci + 1 < ln.length) {
          ci++;
          acc ~= ln[ci];
        } else if (c == quote) {
          inStr = false;
        }
        continue;
      }
      if (c == '"' || c == '\'' || c == '`') {
        inStr = true;
        quote = c;
        acc ~= c;
      } else if (c == '(') {
        if (depth > 0) {
          acc ~= c;
        }
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0) {
          endIdx = li;
          return ParenContentResult(acc, endIdx);
        }
        acc ~= c;
      } else if (depth > 0) {
        acc ~= c;
      }
    }
    acc ~= ' ';
  }
  return ParenContentResult(acc, endIdx);
}

bool isIdentChar(char c) {
  return isAlphaNum(c) || c == '_';
}

/**
 * Returns true when token occurs in source at position pos.
 */
bool startsAt(string source, size_t pos, string token) {
  return pos + token.length <= source.length
    && source[pos .. pos + token.length] == token;
}

/**
 * Returns true when token occurs at pos as a whole word: no identifier
 * character precedes or follows it.
 */
bool isWordAt(string source, size_t pos, string token) {
  const bool wordStart = pos == 0 || !isIdentChar(source[pos - 1]);
  const size_t end = pos + token.length;
  const bool wordEnd = end >= source.length || !isIdentChar(source[end]);
  return wordStart && wordEnd && startsAt(source, pos, token);
}

/**
 * Returns the index just past the first token at or after from, or the
 * source length when the token never occurs.
 */
size_t indexPast(string source, size_t from, string token) {
  size_t p = from;
  while (p < source.length && !startsAt(source, p, token)) {
    p++;
  }
  return p < source.length ? p + token.length : source.length;
}

/**
 * Returns the index just past a comment or a string/char literal starting at
 * pos, or pos when none starts there.
 */
size_t skipNonCode(string source, size_t pos) {
  if (pos >= source.length) {
    return pos;
  }
  const char c = source[pos];
  const char next = pos + 1 < source.length ? source[pos + 1] : '\0';
  if (c == '/' && next == '/') {
    size_t end = pos;
    while (end < source.length && source[end] != '\n') {
      end++;
    }
    return end;
  }
  if (c == '/' && next == '*') {
    return indexPast(source, pos + 2, "*/");
  }
  if (c == '/' && next == '+') {
    size_t p = pos + 2;
    int depth = 1;
    while (p < source.length && depth > 0) {
      if (startsAt(source, p, "/+")) {
        depth++;
        p += 2;
      } else if (startsAt(source, p, "+/")) {
        depth--;
        p += 2;
      } else {
        p++;
      }
    }
    return p;
  }
  if (c == '"' || c == '\'') {
    size_t p = pos + 1;
    while (p < source.length && source[p] != c) {
      p += source[p] == '\\' ? 2 : 1;
    }
    return p < source.length ? p + 1 : source.length;
  }
  if (c == '`') {
    return indexPast(source, pos + 1, "`");
  }
  const bool rawStart = c == 'r' && next == '"'
    && (pos == 0 || !isIdentChar(source[pos - 1]));
  if (rawStart) {
    return indexPast(source, pos + 2, "\"");
  }
  return pos;
}

/**
 * Returns the index of the first character at or after pos that is not white
 * space, or the source length when only white space remains.
 */
size_t skipSpaces(string source, size_t pos) {
  size_t p = pos;
  while (p < source.length && isWhite(source[p])) {
    p++;
  }
  return p;
}

/**
 * Returns the index just past the `openCh ... closeCh` group whose opening
 * character is at open, or the source length when it never closes. Nested
 * groups, comments, and string literals are skipped.
 */
size_t bracketBlockEnd(
  string source,
  size_t open,
  char openCh,
  char closeCh
) {
  int depth = 0;
  size_t p = open;
  while (p < source.length) {
    const size_t next = skipNonCode(source, p);
    if (next > p) {
      p = next;
      continue;
    }
    if (source[p] == openCh) {
      depth++;
    } else if (source[p] == closeCh) {
      depth--;
      if (depth == 0) {
        return p + 1;
      }
    }
    p++;
  }
  return source.length;
}

/**
 * Returns the index just past the `{ ... }` block whose `{` is at open, or
 * the source length when the block never closes.
 */
size_t braceBlockEnd(string source, size_t open) {
  return bracketBlockEnd(source, open, '{', '}');
}

/**
 * Returns the index just past a `unittest { ... }` block starting at start,
 * or start when no such block begins there.
 */
size_t unittestBlockEnd(string source, size_t start) {
  enum keyword = "unittest";
  if (!isWordAt(source, start, keyword)) {
    return start;
  }
  const size_t p = skipSpaces(source, start + keyword.length);
  if (p >= source.length || source[p] != '{') {
    return start;
  }
  return braceBlockEnd(source, p);
}

/**
 * Returns the index just past the comment, string literal, or unittest block
 * starting at pos, or pos when none starts there.
 */
size_t skipIgnored(string source, size_t pos) {
  const size_t unitEnd = unittestBlockEnd(source, pos);
  return unitEnd > pos ? unitEnd : skipNonCode(source, pos);
}

/**
 * Returns the index of the first `{` or `;` in code at or after from, or the
 * source length when neither occurs.
 */
size_t nextBodyStart(string source, size_t from) {
  size_t p = from;
  while (p < source.length) {
    const size_t next = skipNonCode(source, p);
    if (next > p) {
      p = next;
      continue;
    }
    if (source[p] == '{' || source[p] == ';') {
      return p;
    }
    p++;
  }
  return source.length;
}

/**
 * Returns true when name is called as `name(` in code between from and end.
 * Comments, string literals, and unittest blocks are ignored.
 */
bool hasCodeCall(string source, size_t from, size_t end, string name) {
  size_t p = from;
  while (p < end) {
    const size_t next = skipIgnored(source, p);
    if (next > p) {
      p = next;
      continue;
    }
    if (isWordAt(source, p, name)) {
      const size_t q = skipSpaces(source, p + name.length);
      if (q < source.length && source[q] == '(') {
        return true;
      }
    }
    p++;
  }
  return false;
}

/**
 * Returns the 1-based line number of the character at pos.
 */
size_t lineNumberAt(string source, size_t pos) {
  size_t line = 1;
  foreach (char c; source[0 .. pos]) {
    if (c == '\n') {
      line++;
    }
  }
  return line;
}

/**
 * Returns true when path equals one of suffixes or ends with "/" followed by
 * one of them.
 */
bool pathEndsWithAny(string path, string[] suffixes) {
  foreach (suffix; suffixes) {
    if (path == suffix || path.endsWith("/" ~ suffix)) {
      return true;
    }
  }
  return false;
}

/**
 * Returns true when lines fromLine through toLine of filePath overlap a diff
 * span. With no spans (full scan) every range counts.
 */
bool overlapsSpans(
  string filePath,
  size_t fromLine,
  size_t toLine,
  const FileSpan[] spans
) {
  if (spans.length == 0) {
    return true;
  }
  foreach (const ref span; spans) {
    if (span.file == filePath && span.lineCount > 0
      && fromLine < span.startLine + span.lineCount
      && toLine >= span.startLine) {
      return true;
    }
  }
  return false;
}

/**
 * Returns the index of the `(` in `override HandleResult handleEvent(` when
 * that declaration starts at pos, or the source length otherwise.
 */
size_t handleEventParenAt(string source, size_t pos) {
  if (!isWordAt(source, pos, "override")) {
    return source.length;
  }
  size_t p = skipSpaces(source, pos + "override".length);
  if (!isWordAt(source, p, "HandleResult")) {
    return source.length;
  }
  p = skipSpaces(source, p + "HandleResult".length);
  if (!isWordAt(source, p, "handleEvent")) {
    return source.length;
  }
  p = skipSpaces(source, p + "handleEvent".length);
  if (p < source.length && source[p] == '(') {
    return p;
  }
  return source.length;
}

/**
 * Checks that every `override HandleResult handleEvent` body calls
 * super.handleEvent so unhandled events fall through to the base class.
 * The controller and internal directories define that fallback and are
 * skipped. The body is found on the full file, so overlap with diff spans is
 * decided on the whole function.
 */
void checkHandleEventFallback(
  string filePath,
  string content,
  const FileSpan[] diffSpans,
  ref Issue[] issues
) {
  if (filePath.canFind("yguilib/source/yguilib/controller/")
    || filePath.canFind("yguilib/source/yguilib/internal/")) {
    return;
  }
  size_t p = 0;
  while (p < content.length) {
    const size_t next = skipIgnored(content, p);
    if (next > p) {
      p = next;
      continue;
    }
    const size_t paren = handleEventParenAt(content, p);
    if (paren < content.length) {
      const size_t parenEnd = bracketBlockEnd(content, paren, '(', ')');
      const size_t bodyOpen = nextBodyStart(content, parenEnd);
      if (bodyOpen < content.length && content[bodyOpen] == '{') {
        const size_t bodyEnd = braceBlockEnd(content, bodyOpen);
        const size_t declLine = lineNumberAt(content, p);
        const size_t endLine = lineNumberAt(content, bodyEnd - 1);
        if (overlapsSpans(filePath, declLine, endLine, diffSpans)
          && !hasCodeCall(content, bodyOpen, bodyEnd, "super.handleEvent")) {
          issues ~= Issue(filePath, declLine, 1, IssueLevel.error,
            "override HandleResult handleEvent must return "
            ~ "super.handleEvent(ev) for unhandled events.");
        }
      }
    }
    p++;
  }
}

/**
 * A class declaration with a body: its name, the 1-based line of the
 * declaration, and the body span [open, close) in the source.
 */
struct ClassBody {
  string name;
  size_t line;
  size_t open;
  size_t close;
}

/**
 * Returns the class declarations with a body in source, nested ones included.
 * Comments, string literals, and unittest blocks are ignored.
 */
ClassBody[] classBodies(string source) {
  enum keyword = "class";
  ClassBody[] bodies;
  size_t p = 0;
  while (p < source.length) {
    const size_t next = skipIgnored(source, p);
    if (next > p) {
      p = next;
      continue;
    }
    if (isWordAt(source, p, keyword) && (p == 0 || source[p - 1] != '.')) {
      const size_t nameStart = skipSpaces(source, p + keyword.length);
      size_t nameEnd = nameStart;
      while (nameEnd < source.length && isIdentChar(source[nameEnd])) {
        nameEnd++;
      }
      const bool named = nameStart > p + keyword.length
        && nameEnd > nameStart
        && (isAlpha(source[nameStart]) || source[nameStart] == '_');
      const size_t open = nextBodyStart(source, nameEnd);
      if (named && open < source.length && source[open] == '{') {
        bodies ~= ClassBody(
          source[nameStart .. nameEnd],
          lineNumberAt(source, p),
          open,
          braceBlockEnd(source, open)
        );
      }
      p += keyword.length;
      continue;
    }
    p++;
  }
  return bodies;
}

/**
 * Warns when a class body calls startTimer but never calls stopTimer, so an
 * animation timer may keep running when idle. Timer infrastructure files
 * define or drive the timer API and are skipped.
 */
void checkClassTimerPairs(
  string filePath,
  string content,
  const FileSpan[] diffSpans,
  ref Issue[] issues
) {
  string[] infraFiles = [
    "timercontrol.d",
    "internal/timer_service.d",
    "internal/uisystem_impl.d",
    "controller/package.d"
  ];
  if (pathEndsWithAny(filePath, infraFiles)) {
    return;
  }
  foreach (cls; classBodies(content)) {
    const size_t endLine = lineNumberAt(content, cls.close - 1);
    if (!overlapsSpans(filePath, cls.line, endLine, diffSpans)) {
      continue;
    }
    if (hasCodeCall(content, cls.open, cls.close, "startTimer")
      && !hasCodeCall(content, cls.open, cls.close, "stopTimer")) {
      issues ~= Issue(filePath, cls.line, 1, IssueLevel.warning,
        "Class '" ~ cls.name ~ "' starts a timer but never stops one; "
        ~ "stop timers when idle.");
    }
  }
}

/**
 * Scans a file for codestyle violations.
 */
void checkFileContent(
  string filePath,
  string content,
  const FileSpan[] diffSpans,
  size_t maxFuncLines,
  ref Issue[] issues
) {
  string base = baseName(filePath);
  if (hasUppercase(base)) {
    issues ~= Issue(filePath, 1, 1, IssueLevel.error,
      "Source file name must be all lowercase: " ~ base);
  }

  string[] lines = content.splitLines();
  bool isD = extension(filePath) == ".d";
  bool inMultilineComment = false;
  bool inString = false;

  // Visibility section tracking for D files
  // order: public (1) -> protected (2) -> private (3)
  int currentVisOrder = 0;
  bool isClibBinding = filePath.canFind("/clibs/")
    || filePath.startsWith("clibs/");
  ScopeState[] scopes = [ScopeState(false, false, 0, null)];
  bool inConditionalHeader = false;
  bool nextBraceIsType = false;

  // Function length tracking
  int funcStartLine = -1;
  int braceDepth = 0;
  int funcBraceStart = -1;

  // Regex patterns
  auto inlineVisRe = ctRegex!(
    r"^\s*(public|private|protected)\s+(void|int|bool|string|float|double|"
    ~ r"char|auto|class|struct|interface|enum|alias)\s+"
  );
  auto heavyImportRe = ctRegex!(
    r"^\s*import\s+std\.(algorithm|format|regex|datetime)"
  );
  auto publicImportRe = ctRegex!(r"^\s*public\s+import\b");
  auto blockStartRe = ctRegex!(
    r"^\s*(class|struct|interface|union|enum|if|while|for|foreach|"
    ~ r"switch|do|void|auto|override|final)\b"
  );
  auto typeDeclRe = ctRegex!(
    r"^\s*(?:private\s+|public\s+|protected\s+|package(?:\([^)]*\))?\s+)?"
    ~ r"(?:final\s+|abstract\s+|static\s+)*"
    ~ r"(class|struct|interface|enum|union)\s+([A-Za-z_][A-Za-z0-9_]*)"
  );
  auto condBlockRe = ctRegex!(
    r"^\s*(version|static\s+if|debug|unittest)\b"
  );
  auto funcDeclRe = ctRegex!(
    r"^\s*(?:(?:override|final|static|abstract|nothrow|pure|@safe|"
    ~ r"@trusted|@system|@nogc|@property|const|immutable|inout|shared)\s+)*"
    ~ r"(?:[A-Za-z_~][A-Za-z0-9_.*\[\]!<>:, \t]*\s+)?"
    ~ r"([A-Za-z_~][A-Za-z0-9_]*)\s*(?:\([^)]*\)\s*)?\("
  );
  auto ctorDeclRe = ctRegex!(
    r"^\s*(@disable\s+)?this\s*\("
  );

  string prevNonEmptyLine = "";
  size_t prevNonEmptyLineNo = 0;

  foreach (size_t idx, string rawLine; lines) {
    size_t lineNo = idx + 1;
    string trimmed = rawLine.strip();

    // Check multiline comments
    if (inMultilineComment) {
      if (trimmed.canFind("*/")) {
        inMultilineComment = false;
      }
      continue;
    }
    if (trimmed.startsWith("/*")) {
      if (!trimmed.canFind("*/")) {
        inMultilineComment = true;
      }
      continue;
    }
    if (trimmed.startsWith("//") || trimmed.startsWith("*")) {
      continue;
    }

    bool checkThisLine = isLineInSpans(lineNo, diffSpans);

    // 1. Indentation & Tabs
    if (checkThisLine && rawLine.length > 0) {
      size_t leadingSpaces = 0;
      bool hasTab = false;
      foreach (size_t charIdx, char c; rawLine) {
        if (c == '\t') {
          hasTab = true;
          issues ~= Issue(filePath, lineNo, charIdx + 1, IssueLevel.error,
            "Tab characters are not allowed; use 2 spaces per indent level.");
          break;
        } else if (c == ' ') {
          leadingSpaces++;
        } else {
          break;
        }
      }

      // If line is non-empty code, check odd space indentation
      if (!hasTab && leadingSpaces > 0 && trimmed.length > 0) {
        if (leadingSpaces % 2 != 0) {
          // Allow comments starting with '*' in block comments
          if (!trimmed.startsWith("*") && !trimmed.startsWith("//*")) {
            issues ~= Issue(filePath, lineNo, leadingSpaces + 1,
              IssueLevel.warning,
              "Indentation should be a multiple of 2 spaces (found "
              ~ to!string(leadingSpaces) ~ " spaces).");
          }
        }
      }
    }

    // 2. Opening brace '{' on same line
    if (checkThisLine && trimmed == "{") {
      if (prevNonEmptyLine.length > 0) {
        // If previous line ends with something that typically opens a body
        if (prevNonEmptyLine.endsWith(")")
          || prevNonEmptyLine.endsWith("const")
          || prevNonEmptyLine.endsWith("nothrow")
          || prevNonEmptyLine.endsWith("@nogc")
          || prevNonEmptyLine.endsWith("@safe")
          || matchFirst(prevNonEmptyLine, blockStartRe)) {
          issues ~= Issue(filePath, lineNo, 1, IssueLevel.error,
            "Opening brace '{' must be on the same line as the declaration.");
        }
      }
    }

    // 3. D Specific checks
    if (isD) {
      // Check public import re-exports
      if (checkThisLine && !matchFirst(rawLine, publicImportRe).empty) {
        issues ~= Issue(filePath, lineNo, 1, IssueLevel.error,
          "Public import re-exports are not allowed; import modules "
          ~ "explicitly.");
      }

      // Check inline visibility attributes
      if (checkThisLine) {
        auto m = matchFirst(rawLine, inlineVisRe);
        if (!m.empty) {
          issues ~= Issue(filePath, lineNo, 1, IssueLevel.error,
            "Use section visibility (e.g. 'private:') instead of inline '"
            ~ m[1] ~ " " ~ m[2] ~ "'.");
        }
      }

      // Check section visibility order: public -> protected -> private
      if (trimmed == "public:" || trimmed.startsWith("public:")) {
        if (currentVisOrder > 1) {
          issues ~= Issue(filePath, lineNo, 1, IssueLevel.warning,
            "'public:' section declared after protected or private section.");
        }
        currentVisOrder = 1;
      } else if (trimmed == "protected:" || trimmed.startsWith("protected:")) {
        if (currentVisOrder > 2) {
          issues ~= Issue(filePath, lineNo, 1, IssueLevel.warning,
            "'protected:' section declared after private section.");
        }
        currentVisOrder = 2;
      } else if (trimmed == "private:" || trimmed.startsWith("private:")) {
        currentVisOrder = 3;
      }

      // Check top-level heavy Phobos imports
      if (checkThisLine && braceDepth == 0) {
        auto impMatch = matchFirst(rawLine, heavyImportRe);
        if (!impMatch.empty) {
          issues ~= Issue(filePath, lineNo, 1, IssueLevel.warning,
            "Heavy Phobos import 'std." ~ impMatch[1]
            ~ "' should be scoped inside functions if possible.");
        }
      }

      // Check D type names, constructors, overloads, and default params
      // only outside function bodies (module or type scope).
      if (funcStartLine == -1) {
        if (!matchFirst(trimmed, condBlockRe).empty
          || trimmed.startsWith("else")) {
          inConditionalHeader = true;
        }
        auto typeM = matchFirst(rawLine, typeDeclRe);
        if (!typeM.empty) {
          nextBraceIsType = true;
          string typeName = typeM[2];
          if (checkThisLine && !isClibBinding
            && hasConsecutiveCaps(typeName)) {
            issues ~= Issue(filePath, lineNo, 1, IssueLevel.warning,
              "Symbol '" ~ typeName
              ~ "' has consecutive capital letters (use PascalCase).");
          }
        } else {
          auto ctorM = matchFirst(rawLine, ctorDeclRe);
          if (!ctorM.empty) {
            bool isDisabled = ctorM[1].length > 0;
            size_t openCol = cast(size_t) rawLine.indexOf('(');
            auto parenRes = extractParenContent(lines, idx, openCol);
            auto info = inspectParamList(parenRes.content);

            if (checkThisLine && info.hasDefault) {
              issues ~= Issue(filePath, lineNo, 1, IssueLevel.error,
                "Default parameter values are not allowed in constructors.");
            }
            if (checkThisLine && !isClibBinding && info.hasOutParam) {
              issues ~= Issue(filePath, lineNo, 1, IssueLevel.error,
                "Use a returned struct or Nullable!T instead of 'out' "
                ~ "parameters.");
            }
            if (!isDisabled) {
              if (scopes.length > 0 && scopes[$ - 1].isTypeScope) {
                scopes[$ - 1].ctorCount++;
                if (checkThisLine && scopes[$ - 1].ctorCount > 1) {
                  issues ~= Issue(filePath, lineNo, 1, IssueLevel.warning,
                    "Multiple constructors; use a single this() or one "
                    ~ "parameterized constructor.");
                }
              }
              if (checkThisLine && info.paramCount > 3) {
                issues ~= Issue(filePath, lineNo, 1, IssueLevel.warning,
                  "Constructor has " ~ to!string(info.paramCount)
                  ~ " parameters (recommended <= 3).");
              }
            }
          } else {
            auto fnM = matchFirst(rawLine, funcDeclRe);
            bool inDeclScope = scopes.length == 1
              || scopes[$ - 1].isTypeScope
              || scopes[$ - 1].isConditional;
            if (inDeclScope && !fnM.empty && !trimmed.startsWith("alias ")
              && !trimmed.startsWith("return ")
              && !trimmed.startsWith("assert(")
              && !trimmed.startsWith("mixin(")) {
              string fnName = fnM[1];
              if (!isControlOrKeyword(fnName) && fnName != "this") {
                size_t openCol = cast(size_t) rawLine.indexOf('(');
                // If template params precede function params, find last '('
                size_t namePos = cast(size_t) rawLine.indexOf(fnName);
                size_t afterName = namePos + fnName.length;
                auto pIdx = rawLine[afterName .. $].indexOf('(');
                if (pIdx != -1) {
                  openCol = afterName + cast(size_t) pIdx;
                }
                auto parenRes = extractParenContent(lines, idx, openCol);
                // Only treat as declaration if ends with '{' or ';' after ')'
                string tail = lines[parenRes.endIdx].strip();
                if (tail.endsWith("{") || tail.endsWith(";")
                  || tail.endsWith("const") || tail.endsWith("@safe")
                  || tail.endsWith("nothrow") || tail.endsWith("@nogc")) {
                  auto info = inspectParamList(parenRes.content);
                  if (checkThisLine && info.hasDefault) {
                    issues ~= Issue(filePath, lineNo, 1, IssueLevel.error,
                      "Default parameter values are not allowed ('"
                      ~ fnName ~ "').");
                  }
                  if (checkThisLine && !isClibBinding && info.hasOutParam) {
                    issues ~= Issue(filePath, lineNo, 1, IssueLevel.error,
                      "Use a returned struct or Nullable!T instead of 'out' "
                      ~ "parameters.");
                  }
                  if (checkThisLine && !isClibBinding
                    && hasConsecutiveCaps(fnName)) {
                    issues ~= Issue(filePath, lineNo, 1, IssueLevel.warning,
                      "Symbol '" ~ fnName
                      ~ "' has consecutive capital letters.");
                  }
                  if (scopes.length > 0 && !scopes[$ - 1].isConditional
                    && !isOverloadExempt(fnName)) {
                    if (fnName in scopes[$ - 1].funcs) {
                      if (checkThisLine) {
                        issues ~= Issue(filePath, lineNo, 1,
                          IssueLevel.warning,
                          "Overloaded function '" ~ fnName
                          ~ "' (previously declared on line "
                          ~ to!string(scopes[$ - 1].funcs[fnName]) ~ ").");
                      }
                    } else {
                      scopes[$ - 1].funcs[fnName] = lineNo;
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // Track braces and function length
    foreach (char c; rawLine) {
      if (c == '{') {
        bool wasTypeOrCond = nextBraceIsType || inConditionalHeader;
        if (isD) {
          bool isCond = inConditionalHeader
            || (scopes.length > 0 && scopes[$ - 1].isConditional);
          if (nextBraceIsType) {
            currentVisOrder = 0;
          }
          scopes ~= ScopeState(nextBraceIsType, isCond, 0, null);
          nextBraceIsType = false;
          inConditionalHeader = false;
        }
        if (braceDepth == 1 && funcStartLine == -1 && !wasTypeOrCond) {
          funcStartLine = cast(int) lineNo;
          funcBraceStart = braceDepth;
        }
        braceDepth++;
      } else if (c == '}') {
        braceDepth--;
        if (isD && scopes.length > 1) {
          scopes.length--;
        }
        if (funcStartLine != -1 && braceDepth <= funcBraceStart) {
          size_t funcLength = lineNo - funcStartLine + 1;
          if (funcLength > maxFuncLines
            && isLineInSpans(funcStartLine, diffSpans)) {
            issues ~= Issue(filePath, funcStartLine, 1, IssueLevel.warning,
              "Function length (" ~ to!string(funcLength) ~ " lines) exceeds "
              ~ to!string(maxFuncLines) ~ " lines. Consider splitting.");
          }
          funcStartLine = -1;
          funcBraceStart = -1;
        }
      }
    }

    if (trimmed.length > 0) {
      prevNonEmptyLine = trimmed;
      prevNonEmptyLineNo = lineNo;
    }
  }

  // Whole-file rules need the full body of each function or class
  if (isD) {
    checkHandleEventFallback(filePath, content, diffSpans, issues);
    checkClassTimerPairs(filePath, content, diffSpans, issues);
  }
}

int main(string[] args) {
  bool optStaged = false;
  bool optDiff = false;
  bool optAll = false;
  size_t optMaxFuncLines = 50;
  string[] targets;

  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "staged|cached", "Check staged git diff additions", &optStaged,
      "diff", "Check unstaged git diff additions", &optDiff,
      "all", "Scan all tracked source files on disk", &optAll,
      "max-func-lines", "Warn on functions longer than N lines (default 50)",
      &optMaxFuncLines
    );
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return 1;
  }

  if (helpInfo.helpWanted) {
    defaultGetoptPrinter(
      "Usage: check_style.d [options] [files...]\n"
      ~ "Enforces codestyle.md formatting and conventions.\n\n"
      ~ "Rules:\n"
      ~ "  1 brace placement\n"
      ~ "  2 indentation (2 spaces, no tabs)\n"
      ~ "  3 lowercase file names\n"
      ~ "  4 visibility section order (D)\n"
      ~ "  5 scoped heavy Phobos imports (D)\n"
      ~ "  6 function length\n"
      ~ "  7 no default parameter values (D)\n"
      ~ "  8 no overloaded functions (D)\n"
      ~ "  9 no consecutive capital letters (D)\n"
      ~ "  10 constructor constraints (D)\n"
      ~ "  11 no public import re-exports (D)\n"
      ~ "  12 no out parameters (D)\n"
      ~ "  13 handleEvent falls through to super.handleEvent (D)\n"
      ~ "  14 startTimer paired with stopTimer (D)\n\n"
      ~ "Options:",
      helpInfo.options
    );
    return 0;
  }

  targets = args[1 .. $];

  Issue[] issues;

  if (optAll) {
    // Scan all files in source, yguilib, clibs
    string[] dirs = ["source", "yguilib", "yvidtrim-clibs"];
    foreach (d; dirs) {
      if (!exists(d)) {
        continue;
      }
      foreach (entry; dirEntries(d, SpanMode.depth)) {
        if (entry.isFile && isSourceFile(entry.name)) {
          string text = readText(entry.name);
          checkFileContent(entry.name, text, [], optMaxFuncLines, issues);
        }
      }
    }
  } else if (targets.length > 0) {
    // Specific files or directories
    foreach (t; targets) {
      if (isDir(t)) {
        foreach (entry; dirEntries(t, SpanMode.depth)) {
          if (entry.isFile && isSourceFile(entry.name)) {
            string text = readText(entry.name);
            checkFileContent(entry.name, text, [], optMaxFuncLines, issues);
          }
        }
      } else if (isFile(t)) {
        string text = readText(t);
        checkFileContent(t, text, [], optMaxFuncLines, issues);
      } else {
        stderr.writeln("Warning: Target not found: ", t);
      }
    }
  } else {
    // Default: git diff
    string[] diffCmd = ["git", "diff", "-U0"];
    if (optStaged) {
      diffCmd = ["git", "diff", "--cached", "-U0"];
    }
    auto diffRes = execute(diffCmd);
    if (diffRes.status != 0) {
      stderr.writeln("Error executing git diff: ", diffRes.output);
      return 1;
    }

    if (diffRes.output.strip().length == 0) {
      writeln("No modified files to check.");
      return 0;
    }

    FileSpan[] diffSpans = parseGitDiffUnified(diffRes.output);
    string[string] seenFiles;
    foreach (span; diffSpans) {
      if (span.file !in seenFiles && isSourceFile(span.file)
        && exists(span.file)) {
        seenFiles[span.file] = "1";
        string text = readText(span.file);
        checkFileContent(span.file, text, diffSpans, optMaxFuncLines, issues);
      }
    }
  }

  // Print results
  size_t errorCount = 0;
  size_t warnCount = 0;

  foreach (const ref issue; issues) {
    string levelStr = issue.level == IssueLevel.error ? "error" : "warning";
    writefln("%s:%d:%d: [%s] %s", issue.file, issue.line, issue.col,
      levelStr, issue.message);
    if (issue.level == IssueLevel.error) {
      errorCount++;
    } else {
      warnCount++;
    }
  }

  if (errorCount > 0 || warnCount > 0) {
    writefln("Check completed with %d error(s), %d warning(s).",
      errorCount, warnCount);
  } else {
    writeln("All checks passed cleanly.");
  }

  return errorCount > 0 ? 1 : 0;
}
