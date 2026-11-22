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
