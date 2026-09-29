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
 */
module check_style;

import core.sys.posix.sys.stat : fstat, stat_t, S_ISFIFO, S_ISREG;
import std.algorithm : canFind, countUntil;
import std.conv : to;
import std.file : dirEntries, exists, isDir, isFile, readText, SpanMode;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : baseName, extension;
import std.process : execute;
import std.regex : ctRegex, matchFirst;
import std.stdio : stderr, stdin, writeln, writefln;
import std.string : endsWith, indexOf, isNumeric, splitLines, startsWith, strip;

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
    r"^\s*import\s+std\.(algorithm|format|json|regex|datetime)"
  );
  auto blockStartRe = ctRegex!(
    r"^\s*(class|struct|interface|union|enum|if|while|for|foreach|"
    ~ r"switch|do|void|auto|override|final)\b"
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
    }

    // Track braces and function length
    foreach (char c; rawLine) {
      if (c == '{') {
        if (braceDepth == 1 && funcStartLine == -1) {
          funcStartLine = cast(int) lineNo;
          funcBraceStart = braceDepth;
        }
        braceDepth++;
      } else if (c == '}') {
        braceDepth--;
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
