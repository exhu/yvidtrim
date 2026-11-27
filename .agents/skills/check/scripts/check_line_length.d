#!/usr/bin/env rdmd
/**
 * Checks line length and optional file line-count violations on git diffs
 * or full files on disk.
 */
module check_line_length;

import core.sys.posix.sys.stat : fstat, stat_t, S_ISFIFO, S_ISREG;
import std.conv : ConvException, to;
import std.file : exists, isFile, readText;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.process : execute;
import std.stdio : stderr, stdin, writefln, writeln;
import std.string : endsWith, indexOf, isNumeric, splitLines, startsWith, strip;
import std.typecons : Nullable, nullable;

struct Violation {
  string file;
  size_t line;
  size_t length;
  size_t limit;
  string content;
}

struct Options {
  size_t maxWidth = 80;
  size_t maxLines = 0;
  size_t tabWidth = 4;
  bool staged = false;
  bool forceStdin = false;
  bool fullFileMode = false;
}

/**
 * Calculates visual column width expanding tab stops.
 */
size_t visualLength(string s, size_t tabWidth) {
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
 * Checks raw lines against maxWidth and optional maxLines limit.
 */
Violation[] checkRawLines(
  string sourceName,
  const(string)[] lines,
  size_t maxWidth,
  size_t tabWidth,
  size_t maxLines
) {
  Violation[] violations;
  if (maxLines > 0 && lines.length > maxLines) {
    violations ~= Violation(
      sourceName,
      lines.length,
      lines.length,
      maxLines,
      "Total line count exceeds limit"
    );
  }
  foreach (size_t idx, line; lines) {
    size_t len = visualLength(line, tabWidth);
    if (len > maxWidth) {
      violations ~= Violation(sourceName, idx + 1, len, maxWidth, line);
    }
  }
  return violations;
}

/**
 * Checks all lines in a file on disk against maxWidth and maxLines.
 */
Violation[] checkFileLines(
  string filePath,
  size_t maxWidth,
  size_t tabWidth,
  size_t maxLines
) {
  try {
    string content = readText(filePath);
    return checkRawLines(
      filePath, content.splitLines(), maxWidth, tabWidth, maxLines
    );
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
  import std.algorithm : canFind;

  Violation[] violations;
  string currentFile = "";
  size_t currentLineNum = 0;
  bool inHunk = false;

  foreach (line; lines) {
    if (line.startsWith("diff --git ") || line.startsWith("--- ")) {
      inHunk = false;
      continue;
    }
    if (line.startsWith("+++ ")) {
      inHunk = false;
      currentFile = parseDiffTargetPath(line[4 .. $].strip);
      continue;
    }
    if (line.startsWith("@@ ") && line.canFind(" @@")) {
      auto parsed = parseHunkStartLine(line);
      inHunk = !parsed.isNull;
      if (inHunk) {
        currentLineNum = parsed.get;
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
        violations ~= Violation(currentFile, lineNum, len, maxWidth, content);
      }
    } else if (line.startsWith(" ")) {
      currentLineNum++;
    }
  }
  return violations;
}

string parseDiffTargetPath(string path) {
  if (path.startsWith("b/")) {
    return path[2 .. $];
  }
  return (path != "/dev/null") ? path : "";
}

Nullable!size_t parseHunkStartLine(string line) {
  auto endIdx = line[3 .. $].indexOf(" @@");
  if (endIdx == -1) {
    return Nullable!size_t.init;
  }
  string header = line[3 .. 3 + endIdx];
  auto plusIdx = header.indexOf('+');
  if (plusIdx == -1) {
    return Nullable!size_t.init;
  }
  string newPart = header[plusIdx + 1 .. $];
  auto commaIdx = newPart.indexOf(',');
  string lineStr = (commaIdx != -1) ? newPart[0 .. commaIdx] : newPart;
  try {
    return nullable(lineStr.strip.to!size_t);
  } catch (ConvException) {
    return Nullable!size_t.init;
  }
}

void appendUniqueViolations(
  ref Violation[] dest,
  ref bool[string] seen,
  const(Violation)[] src
) {
  import std.format : format;

  foreach (v; src) {
    string key = format("%s:%d:%s", v.file, v.line, v.content);
    if (key !in seen) {
      seen[key] = true;
      dest ~= v;
    }
  }
}

bool runGitDiffCheck(
  string[] cmd,
  size_t maxWidth,
  size_t tabWidth,
  ref Violation[] violations,
  ref bool[string] seen
) {
  auto res = execute(cmd);
  if (res.status != 0) {
    stderr.writefln(
      "git diff failed with exit code %d: %s", res.status, res.output
    );
    return false;
  }
  auto found = checkDiffLines(res.output.splitLines(), maxWidth, tabWidth);
  appendUniqueViolations(violations, seen, found);
  return true;
}

bool checkRenamedStagedFiles(
  size_t maxWidth,
  size_t tabWidth,
  size_t maxLines,
  ref Violation[] violations,
  ref bool[string] seen
) {
  auto res = execute([
    "git", "diff", "--cached", "--name-only", "--diff-filter=R"
  ]);
  if (res.status != 0) {
    return true;
  }
  foreach (rawPath; res.output.splitLines()) {
    string path = rawPath.strip;
    if (path.length > 0 && exists(path) && isFile(path)) {
      auto found = checkFileLines(path, maxWidth, tabWidth, maxLines);
      appendUniqueViolations(violations, seen, found);
    }
  }
  return true;
}

bool isAllUntrackedFiles(const(string)[] targets) {
  if (targets.length == 0) {
    return false;
  }
  foreach (t; targets) {
    if (!exists(t) || !isFile(t) || isTrackedInGit(t)) {
      return false;
    }
  }
  return true;
}

bool runFullFileChecks(
  const(string)[] targets,
  bool useStdin,
  in Options opts,
  ref Violation[] violations
) {
  if (useStdin) {
    string[] rawLines;
    foreach (line; stdin.byLineCopy()) {
      rawLines ~= line;
    }
    violations = checkRawLines(
      "<stdin>", rawLines, opts.maxWidth, opts.tabWidth, opts.maxLines
    );
    return true;
  }
  if (targets.length == 0) {
    stderr.writeln("Error: --file requires at least one file path target");
    return false;
  }
  foreach (target; targets) {
    if (!exists(target) || !isFile(target)) {
      stderr.writefln("Error: File not found: %s", target);
      return false;
    }
    violations ~= checkFileLines(
      target, opts.maxWidth, opts.tabWidth, opts.maxLines
    );
  }
  return true;
}

bool runGitModeChecks(
  const(string)[] targets,
  bool useStdin,
  in Options opts,
  ref Violation[] violations
) {
  if (useStdin) {
    string[] diffLines;
    foreach (line; stdin.byLineCopy()) {
      diffLines ~= line;
    }
    violations = checkDiffLines(diffLines, opts.maxWidth, opts.tabWidth);
    return true;
  }

  bool[string] seen;
  if (targets.length == 0 && !opts.staged) {
    if (!runGitDiffCheck(
        ["git", "diff", "-U0"], opts.maxWidth, opts.tabWidth, violations, seen
      )) {
      return false;
    }
    if (!runGitDiffCheck(
        ["git", "diff", "-U0", "--cached"],
        opts.maxWidth, opts.tabWidth, violations, seen
      )) {
      return false;
    }
    return checkRenamedStagedFiles(
      opts.maxWidth, opts.tabWidth, opts.maxLines, violations, seen
    );
  }

  string[] cmd = ["git", "diff", "-U0"];
  if (opts.staged) {
    cmd ~= "--cached";
  }
  cmd ~= targets;
  return runGitDiffCheck(cmd, opts.maxWidth, opts.tabWidth, violations, seen);
}

int main(string[] args) {
  Options opts;
  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "w|max-width", "Maximum visual column width (default: 80)",
      &opts.maxWidth,
      "m|max-lines", "Maximum total lines per file (0 = unlimited)",
      &opts.maxLines,
      "t|tab-width", "Tab stop column width (default: 4)", &opts.tabWidth,
      "f|file", "Check entire file(s) on disk instead of git diff",
      &opts.fullFileMode,
      "staged|cached", "Check staged git changes only", &opts.staged,
      "stdin", "Force reading diff or lines from standard input",
      &opts.forceStdin
    );
  } catch (Exception e) {
    stderr.writefln("Error: %s", e.msg);
    return 1;
  }

  if (helpInfo.helpWanted) {
    defaultGetoptPrinter(
      "Usage: check_line_length.d [options] [target/file...] [max-width]\n\n" ~
      "Checks line-length and optional line-count violations on git diffs\n" ~
      "or full files on disk.\n",
      helpInfo.options
    );
    return 0;
  }

  string[] targets;
  foreach (arg; args[1 .. $]) {
    if (arg.isNumeric) {
      opts.maxWidth = arg.to!size_t;
    } else {
      targets ~= arg;
    }
  }

  const bool useStdin = opts.forceStdin ||
    (isStdinPiped() && targets.length == 0);
  if (!opts.fullFileMode && isAllUntrackedFiles(targets)) {
    opts.fullFileMode = true;
  }

  Violation[] violations;
  const bool ok = opts.fullFileMode
    ? runFullFileChecks(targets, useStdin, opts, violations)
    : runGitModeChecks(targets, useStdin, opts, violations);
  if (!ok) {
    return 1;
  }

  if (violations.length == 0) {
    writeln("Line length check passed (0 violations).");
    return 0;
  }

  foreach (v; violations) {
    writefln(
      "%s:%d: [%d/%d] %s",
      v.file.length ? v.file : "<input>", v.line, v.length, v.limit, v.content
    );
  }
  return 1;
}
