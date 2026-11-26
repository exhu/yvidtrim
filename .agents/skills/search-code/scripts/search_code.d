#!/usr/bin/env rdmd
/**
 * Searches D/C sources, docs, and skills using regex or whole-word patterns
 * with project-aware excludes and zero-match verification.
 */
module search_code;

import std.file : dirEntries, exists, isDir, isFile, readText, SpanMode;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : baseName, buildPath, extension;
import std.stdio : stderr, writefln, writeln;
import std.string : splitLines, toLower;

struct Options {
  bool wholeWord = false;
  bool ignoreCase = false;
  bool includeDocs = false;
  bool includeSkills = false;
  bool includePlans = false;
  bool includeArchive = false;
  bool expectNone = false;
  bool countOnly = false;
  bool jsonOutput = false;
  size_t maxMatches = 0;
}

struct SearchMatch {
  string file;
  size_t line;
  string text;
}

struct FileCount {
  string file;
  size_t count;
}

bool isExcludedDir(string name, bool includeArchive) {
  if (name == "_build" || name == "_bench" || name == ".git" ||
      name == ".dub" || name == ".cache" || name == "subprojects") {
    return true;
  }
  return !includeArchive && name == "archive";
}

bool isBinaryExt(string ext) {
  string lower = ext.toLower();
  switch (lower) {
    case ".png":
    case ".jpg":
    case ".jpeg":
    case ".ttf":
    case ".otf":
    case ".o":
    case ".a":
    case ".so":
    case ".bin":
    case ".pdf":
    case ".mp4":
    case ".mkv":
    case ".wav":
    case ".zip":
    case ".gz":
    case ".ico":
      return true;
    default:
      return false;
  }
}

void walkDir(string dir, bool includeArchive, ref string[] files) {
  foreach (entry; dirEntries(dir, SpanMode.shallow)) {
    string name = baseName(entry.name);
    if (entry.isDir) {
      if (!isExcludedDir(name, includeArchive)) {
        walkDir(entry.name, includeArchive, files);
      }
    } else if (entry.isFile && !isBinaryExt(extension(name))) {
      files ~= entry.name;
    }
  }
}

string[] defaultSearchRoots(const Options opts) {
  string[] roots = [
    "source", "yguilib/source", "yguilib/examples", "yguilib/benchmarks"
  ];
  if (opts.includeDocs) {
    roots ~= "documentation";
  }
  if (opts.includeSkills) {
    roots ~= ".agents/skills";
  }
  if (opts.includePlans) {
    roots ~= "plans";
  }
  return roots;
}

string[] collectSearchFiles(const Options opts, string[] explicitPaths) {
  import std.algorithm : sort;

  string[] roots = explicitPaths.length > 0
    ? explicitPaths
    : defaultSearchRoots(opts);
  string[] files;
  foreach (r; roots) {
    if (!exists(r)) {
      if (explicitPaths.length > 0) {
        stderr.writefln("Warning: path not found: %s", r);
      }
      continue;
    }
    if (isDir(r)) {
      walkDir(r, opts.includeArchive, files);
    } else if (isFile(r) && !isBinaryExt(extension(r))) {
      files ~= r;
    }
  }
  sort(files);
  return files;
}

bool searchFile(
  string file,
  string[] rawPatterns,
  const Options opts,
  ref SearchMatch[] matches,
  ref FileCount[] counts
) {
  import std.regex : matchFirst, regex, Regex;

  string content;
  try {
    content = readText(file);
  } catch (Exception e) {
    stderr.writefln("Warning: could not read %s: %s", file, e.msg);
    return true;
  }

  Regex!char[] compiled;
  try {
    foreach (p; rawPatterns) {
      string pat = opts.wholeWord ? `\b(?:` ~ p ~ `)\b` : p;
      compiled ~= opts.ignoreCase ? regex(pat, "i") : regex(pat);
    }
  } catch (Exception e) {
    stderr.writefln("Error: invalid regex: %s", e.msg);
    return false;
  }

  size_t fileHits = 0;
  foreach (idx, line; content.splitLines()) {
    foreach (re; compiled) {
      if (!matchFirst(line, re).empty) {
        fileHits++;
        matches ~= SearchMatch(file, idx + 1, line);
        break;
      }
    }
  }
  if (fileHits > 0) {
    counts ~= FileCount(file, fileHits);
  }
  return true;
}

void printJsonResults(
  const SearchMatch[] matches,
  const FileCount[] counts
) {
  import std.json : JSONValue;

  JSONValue[] mArr;
  foreach (m; matches) {
    mArr ~= JSONValue([
      "file": JSONValue(m.file),
      "line": JSONValue(m.line),
      "text": JSONValue(m.text)
    ]);
  }
  JSONValue[] cArr;
  foreach (c; counts) {
    cArr ~= JSONValue([
      "file": JSONValue(c.file),
      "count": JSONValue(c.count)
    ]);
  }
  JSONValue root = [
    "matchCount": JSONValue(matches.length),
    "fileCount": JSONValue(counts.length),
    "counts": JSONValue(cArr),
    "matches": JSONValue(mArr)
  ];
  writeln(root.toPrettyString());
}

void printTextResults(
  const SearchMatch[] matches,
  const FileCount[] counts,
  const Options opts
) {
  if (opts.countOnly) {
    foreach (c; counts) {
      writefln("%s: %d", c.file, c.count);
    }
    writefln("Total: %d match(es) across %d file(s).",
      matches.length, counts.length);
    return;
  }
  if (matches.length == 0) {
    writeln(opts.expectNone ? "0 matches (OK)." : "0 matches.");
    return;
  }
  size_t limit = opts.maxMatches > 0 ? opts.maxMatches : matches.length;
  foreach (idx, m; matches) {
    if (idx >= limit) {
      writefln("... truncated (%d more match(es)).", matches.length - limit);
      break;
    }
    writefln("%s:%d: %s", m.file, m.line, m.text);
  }
}

bool resolvePatternsAndPaths(
  string[] positional,
  ref string[] patterns,
  ref string[] paths
) {
  if (patterns.length == 0) {
    if (positional.length == 0) {
      return false;
    }
    patterns ~= positional[0];
    paths = positional.length > 1 ? positional[1 .. $] : [];
    return true;
  }
  paths = positional;
  return true;
}

int main(string[] args) {
  Options opts;
  string[] patterns;
  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "pattern|e", "Regex pattern to search (repeatable)", &patterns,
      "word|w", "Match whole identifier words only", &opts.wholeWord,
      "ignore-case|i", "Case-insensitive regex matching", &opts.ignoreCase,
      "include-docs", "Include documentation/ in default roots",
        &opts.includeDocs,
      "include-skills", "Include .agents/skills/ in default roots",
        &opts.includeSkills,
      "include-plans", "Include plans/ in default roots", &opts.includePlans,
      "include-archive", "Do not skip archive/ directories",
        &opts.includeArchive,
      "expect-none", "Exit 1 if any match is found (0 if none)",
        &opts.expectNone,
      "count", "Print per-file and total match counts only", &opts.countOnly,
      "max-matches", "Stop printing matches after N lines (0 = all)",
        &opts.maxMatches,
      "json", "Output matches in JSON format", &opts.jsonOutput
    );
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return 2;
  }

  string[] paths;
  string[] positional = args.length > 1 ? args[1 .. $] : [];
  if (helpInfo.helpWanted || !resolvePatternsAndPaths(positional, patterns,
      paths)) {
    defaultGetoptPrinter(
      "Usage: rdmd search_code.d [options] <pattern> [paths...]",
      helpInfo.options
    );
    return helpInfo.helpWanted ? 0 : 2;
  }

  string[] files = collectSearchFiles(opts, paths);
  SearchMatch[] matches;
  FileCount[] counts;
  foreach (file; files) {
    if (!searchFile(file, patterns, opts, matches, counts)) {
      return 2;
    }
  }
  if (opts.jsonOutput) {
    printJsonResults(matches, counts);
  } else {
    printTextResults(matches, counts, opts);
  }
  return (opts.expectNone && matches.length > 0) ? 1 : 0;
}
