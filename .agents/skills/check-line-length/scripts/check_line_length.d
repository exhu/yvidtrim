#!/usr/bin/env rdmd
/**
 * Checks line length violations on git diffs or full files on disk.
 */
module check_line_length;

import core.sys.posix.sys.stat : fstat, stat_t, S_ISFIFO, S_ISREG;
import std.algorithm : canFind;
import std.conv : ConvException, to;
import std.file : exists, isFile, readText;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.process : execute;
import std.stdio : stderr, stdin, writefln;
import std.string : endsWith, indexOf, isNumeric, splitLines, startsWith, strip;

struct Violation {
  string file;
  size_t line;
  size_t length;
  size_t limit;
  string content;
}

/**
 * Calculates visual column width expanding tab stops.
 */
size_t visualLength(string s, size_t tabWidth = 4) {
  if (s.endsWith("\r")) {
    s = s[0 .. $ - 1];
  }
  size_t col = 0;
  foreach (dchar c; s) {
    if (c == '\t') {
      col += tabWidth - (col % tabWidth);
    } else {
      col += 1;
    }
  }
  return col;
}

/**
 * Checks if stdin is connected to a pipe or redirected file.
 */
bool isStdinPiped() {
  stat_t st;
  if (fstat(0, &st) == 0) {
    return (S_ISFIFO(st.st_mode) || S_ISREG(st.st_mode)) != 0;
  }
  return false;
}

/**
 * Checks whether a given path is tracked in the git repository.
 */
bool isTrackedInGit(string path) {
  auto res = execute(["git", "ls-files", "--error-unmatch", "--", path]);
  return res.status == 0;
}

/**
 * Checks raw lines against maxWidth (used for full file scans).
 */
Violation[] checkRawLines(
  string sourceName,
  const(string)[] lines,
  size_t maxWidth,
  size_t tabWidth
) {
  Violation[] violations;
  foreach (size_t idx, line; lines) {
    size_t len = visualLength(line, tabWidth);
    if (len > maxWidth) {
      violations ~= Violation(
        sourceName,
        idx + 1,
        len,
        maxWidth,
        line
      );
    }
  }
  return violations;
}

/**
 * Checks all lines in a file on disk against maxWidth.
 */
Violation[] checkFileLines(
  string filePath,
  size_t maxWidth,
  size_t tabWidth
) {
  try {
    string content = readText(filePath);
    return checkRawLines(filePath, content.splitLines(), maxWidth, tabWidth);
  } catch (Exception e) {
    stderr.writefln("Error reading %s: %s", filePath, e.msg);
    return [];
  }
}

/**
 * Parses unified diff lines and finds added lines exceeding maxWidth.
 */
Violation[] checkDiffLines(
  const(string)[] lines,
  size_t maxWidth,
  size_t tabWidth
) {
  Violation[] violations;
  string currentFile = "";
  size_t currentLineNum = 0;
  bool inHunk = false;

  foreach (line; lines) {
    if (line.startsWith("diff --git ")) {
      inHunk = false;
      continue;
    }
    if (line.startsWith("--- ")) {
      inHunk = false;
      continue;
    }
    if (line.startsWith("+++ ")) {
      inHunk = false;
      string path = line[4 .. $].strip;
      if (path.startsWith("b/")) {
        currentFile = path[2 .. $];
      } else if (path != "/dev/null") {
        currentFile = path;
      } else {
        currentFile = "";
      }
      continue;
    }
    if (line.startsWith("@@ ") && line.canFind(" @@")) {
      auto endIdx = line[3 .. $].indexOf(" @@");
      if (endIdx != -1) {
        string header = line[3 .. 3 + endIdx];
        auto plusIdx = header.indexOf('+');
        if (plusIdx != -1) {
          string newPart = header[plusIdx + 1 .. $];
          auto commaIdx = newPart.indexOf(',');
          string lineStr = (commaIdx != -1) ? newPart[0 .. commaIdx] : newPart;
          try {
            currentLineNum = lineStr.strip.to!size_t;
            inHunk = true;
          } catch (ConvException) {
            inHunk = false;
          }
        }
      }
      continue;
    }

    if (!inHunk) {
      continue;
    }

    if (line.startsWith("+")) {
      size_t lineNum = currentLineNum++;
      string content = line[1 .. $];
      size_t len = visualLength(content, tabWidth);
      if (len > maxWidth) {
        violations ~= Violation(
          currentFile,
          lineNum,
          len,
          maxWidth,
          content
        );
      }
    } else if (line.startsWith("-")) {
      // Deleted lines do not advance line number in target file
    } else if (line.startsWith(" ")) {
      // Context line advances line number
      currentLineNum++;
    }
  }

  return violations;
}

int main(string[] args) {
  size_t maxWidth = 80;
  size_t tabWidth = 4;
  bool staged = false;
  bool forceStdin = false;
  bool fullFileMode = false;

  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "w|max-width", "Maximum visual column width (default: 80)", &maxWidth,
      "t|tab-width", "Tab stop column width (default: 4)", &tabWidth,
      "f|file", "Check entire file(s) on disk instead of git diff",
      &fullFileMode,
      "staged|cached", "Check staged git changes", &staged,
      "stdin", "Force reading diff or lines from standard input", &forceStdin
    );
  } catch (Exception e) {
    stderr.writefln("Error: %s", e.msg);
    return 1;
  }

  if (helpInfo.helpWanted) {
    defaultGetoptPrinter(
      "Usage: check_line_length.d [options] [target/file...] [max-width]\n\n" ~
      "Checks line-length violations on git diffs or full files.\n" ~
      "Reads from git diff, files on disk, or standard input if piped.\n",
      helpInfo.options
    );
    return 0;
  }

  string[] positional = args[1 .. $];
  string[] targets;

  foreach (arg; positional) {
    if (arg.isNumeric) {
      maxWidth = arg.to!size_t;
    } else {
      targets ~= arg;
    }
  }

  const bool useStdin = forceStdin ||
    (isStdinPiped() && targets.length == 0);

  // If -f/--file was not specified, check if targets are untracked disk files.
  // Untracked files have no git diff history, so default to full file scan.
  if (!fullFileMode && targets.length > 0) {
    bool allUntrackedFiles = true;
    foreach (t; targets) {
      if (!exists(t) || !isFile(t) || isTrackedInGit(t)) {
        allUntrackedFiles = false;
        break;
      }
    }
    if (allUntrackedFiles) {
      fullFileMode = true;
    }
  }

  Violation[] violations;

  if (fullFileMode) {
    if (useStdin) {
      string[] rawLines;
      foreach (line; stdin.byLineCopy()) {
        rawLines ~= line;
      }
      violations = checkRawLines("<stdin>", rawLines, maxWidth, tabWidth);
    } else {
      if (targets.length == 0) {
        stderr.writeln("Error: --file requires at least one file path target");
        return 1;
      }
      foreach (target; targets) {
        if (exists(target) && isFile(target)) {
          violations ~= checkFileLines(target, maxWidth, tabWidth);
        } else {
          stderr.writefln("Error: File not found: %s", target);
          return 1;
        }
      }
    }
  } else {
    string[] diffLines;

    if (useStdin) {
      foreach (line; stdin.byLineCopy()) {
        diffLines ~= line;
      }
    } else {
      string[] cmd = ["git", "diff", "-U0"];
      if (staged) {
        cmd ~= "--cached";
      }
      if (targets.length > 0) {
        cmd ~= targets;
      }

      auto res = execute(cmd);
      if (res.status != 0) {
        stderr.writefln("git diff failed with exit code %d: %s",
          res.status, res.output);
        return 1;
      }
      diffLines = res.output.splitLines();
    }

    violations = checkDiffLines(diffLines, maxWidth, tabWidth);
  }

  if (violations.length == 0) {
    return 0;
  }

  foreach (v; violations) {
    writefln("%s:%d: [%d/%d] %s",
      v.file.length ? v.file : "<input>",
      v.line,
      v.length,
      v.limit,
      v.content
    );
  }

  return 1;
}
