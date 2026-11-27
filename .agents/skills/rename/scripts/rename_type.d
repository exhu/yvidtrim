/**
 * Renames a type identifier across D, C, and optional Markdown files.
 */
module rename_type;

import std.algorithm : filter;
import std.array : array;
import std.file : readText, write;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.stdio : stderr, writefln, writeln;
import std.string : endsWith, indexOf;

import rename_common;

struct Options {
  bool apply = false;
  bool includeDocs = false;
  bool includeSkills = false;
  bool skipComments = false;
  bool skipStrings = false;
  bool checkCollision = true;
  bool jsonOutput = false;
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

void printJson(
  const Match[] matches,
  const string[] collisions,
  const string[] lengthWarnings,
  const string[] fileHints,
  bool applied
) {
  import std.json : JSONValue;

  JSONValue root = [
    "applied": JSONValue(applied),
    "matchCount": JSONValue(matches.length),
    "matches": JSONValue(matchesToJson(matches)),
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

/** Spans of `target` in `content`, lexed by file type. */
Span[] findIdent(string file, string content, string target) {
  Span[] spans;
  scope TokenHandler onToken = (kind, line, lineStart, ref i) {
    const size_t start = i;
    skipIdent(content, i);
    if (content[start .. i] == target) {
      spans ~= Span(start, i, line, start - lineStart + 1, kind);
    }
  };
  if (file.endsWith(".md")) {
    scanMarkdown(content, onToken);
  } else {
    scanSource(content, file.endsWith(".d"), onToken);
  }
  return spans;
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

  if (opts.checkCollision && !file.endsWith(".md")) {
    foreach (cs; findIdent(file, content, newType)) {
      if (cs.kind == MatchKind.code) {
        import std.format : format;
        summary.collisions ~= format("%s:%d:%d", file, cs.line, cs.col);
      }
    }
  }

  Span[] spans = findIdent(file, content, oldType)
    .filter!(sp => isKindEnabled(
      sp.kind, opts.skipComments, opts.skipStrings))
    .array;
  if (spans.length == 0) {
    return;
  }
  addMatches(file, content, spans, summary.matches);

  string updated = applySpans(content, spans, newType);
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
  printMatchLines(summary.matches);
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

int runTypeRename(string[] args) {
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
      "Usage: rdmd rename.d type [options] <OldType> <NewType> [paths...]",
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
  string[] files = collectFiles(
    opts.includeDocs, opts.includeSkills, explicitPaths);
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
