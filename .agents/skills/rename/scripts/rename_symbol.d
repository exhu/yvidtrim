/**
 * Renames a D/C symbol (variable, function, method, field, property,
 * constant, or enum member) with scope, owner, and member-access filters.
 */
module rename_symbol;

import std.algorithm : filter;
import std.array : array;
import std.conv : to;
import std.file : exists, isFile, readText, write;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.stdio : stderr, writefln, writeln;
import std.string : endsWith, indexOf, split, splitLines, startsWith;

import rename_common;

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

struct ScanSummary {
  Match[] matches;
  string[] collisions;
  string[] lengthWarnings;
  size_t filesChanged;
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

/** Spans of `target` in `content`; code matches are sub-classified. */
Span[] findIdent(string file, string content, string target) {
  Span[] spans;
  scope TokenHandler onToken = (region, line, lineStart, ref i) {
    const size_t start = i;
    skipIdent(content, i);
    if (content[start .. i] != target) {
      return;
    }
    const kind = region == MatchKind.code
      ? classifyCodeIdent(content, start, i)
      : region;
    spans ~= Span(start, i, line, start - lineStart + 1, kind);
  };
  if (file.endsWith(".md")) {
    scanMarkdown(content, onToken);
  } else {
    scanSource(content, file.endsWith(".d"), onToken);
  }
  return spans;
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
  return isKindEnabled(sp.kind, opts.skipComments, opts.skipStrings);
}

bool hasOwnerInCode(string file, string content, string ownerType) {
  foreach (os; findIdent(file, content, ownerType)) {
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
  const Options opts,
  ref string[] collisions
) {
  foreach (cs; findIdent(file, content, newSym)) {
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

  if (opts.ownerType.length > 0 &&
      (isMd || !hasOwnerInCode(file, content, opts.ownerType))) {
    return;
  }

  if (!opts.findOnly && opts.checkCollision && !isMd) {
    collectCollisions(file, content, newSym, opts, summary.collisions);
  }

  Span[] spans = findIdent(file, content, oldSym)
    .filter!(sp => shouldReplace(sp, opts))
    .array;
  if (spans.length == 0) {
    return;
  }
  addMatches(file, content, spans, summary.matches);

  if (opts.findOnly) {
    summary.filesChanged++;
    return;
  }

  string updated = applySpans(content, spans, newSym);
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

  JSONValue root = [
    "applied": JSONValue(applied),
    "matchCount": JSONValue(summary.matches.length),
    "matches": JSONValue(matchesToJson(summary.matches)),
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
    results ~= JSONValue([
      "oldSymbol": JSONValue(rep.oldSym),
      "newSymbol": JSONValue(rep.newSym),
      "matchCount": JSONValue(rep.summary.matches.length),
      "filesCount": JSONValue(rep.summary.filesChanged),
      "matches": JSONValue(matchesToJson(rep.summary.matches)),
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
    printMatchLines(rep.summary.matches);
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

int runSymbolRename(string[] args) {
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
      "Usage: rdmd rename.d symbol [options] <OldSymbol> <NewSymbol> [paths]",
      helpInfo.options
    );
    return helpInfo.helpWanted ? 0 : 2;
  }
  if (!parseLineRange(linesSpec, opts.lines)) {
    stderr.writefln("Error: invalid --lines range '%s'", linesSpec);
    return 2;
  }

  string[] files = collectFiles(
    opts.includeDocs, opts.includeSkills, explicitPaths);
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
