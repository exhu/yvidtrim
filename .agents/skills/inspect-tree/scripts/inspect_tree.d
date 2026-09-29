#!/usr/bin/env rdmd
/**
 * Project tree and file classifier for yvidtrim and yguilib.
 * Helps identify:
 *  - D modules (with declared module names and role: facade, internal, test)
 *  - C/C++ files (headers, sources, wrapper tests)
 *  - Build configuration files (Meson, Dub, wrap subprojects)
 *  - Documentation files (Markdown, text guides)
 */
module inspect_tree;

import std.conv : to;
import std.file : dirEntries, exists, isDir, isFile, readText, SpanMode;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : baseName, buildNormalizedPath, dirName, extension;
import std.stdio : stderr, stdout, writeln, writefln;
import std.string : indexOf, replace, splitLines, strip;

public:

enum FileCategory {
  dModule,
  cFile,
  buildConfig,
  doc,
  other
}

struct FileEntry {
  string path;
  string relPath;
  FileCategory category;
  string subCategory;
  string identifier;
  size_t lineCount;
}

struct ScanOptions {
  bool showDModules = false;
  bool showCFiles = false;
  bool showBuildConfigs = false;
  bool showDocs = false;
  bool showTree = false;
  bool showSummary = false;
  bool showJson = false;
  bool includeAll = false;
  size_t maxDepth = 20;
}

int main(string[] args) {
  ScanOptions opt;
  GetoptResult res;
  try {
    res = getopt(
      args,
      "d|d-modules", "Show only D modules with declared module names",
      &opt.showDModules,
      "c|c-files", "Show only C/C++ source and header files",
      &opt.showCFiles,
      "b|build-configs", "Show only build configurations (Meson, Dub)",
      &opt.showBuildConfigs,
      "m|docs", "Show only documentation files (*.md, *.txt)",
      &opt.showDocs,
      "t|tree", "Display files as a visual hierarchy tree",
      &opt.showTree,
      "s|summary", "Display summary counts table only",
      &opt.showSummary,
      "j|json", "Output structured JSON array",
      &opt.showJson,
      "a|all", "Include hidden files and build output directories",
      &opt.includeAll,
      "max-depth", "Maximum directory recursion depth (default: 20)",
      &opt.maxDepth
    );
  } catch (Exception ex) {
    stderr.writefln("Error: %s", ex.msg);
    return 1;
  }

  if (res.helpWanted) {
    printHelp(res);
    return 0;
  }

  string[] targets = args.length > 1 ? args[1 .. $] : ["."];
  FileEntry[] entries;

  foreach (target; targets) {
    if (!exists(target)) {
      stderr.writefln("Error: Target path does not exist: %s", target);
      return 1;
    }
    scanPath(target, entries, opt, 0);
  }

  import std.algorithm.sorting : sort;
  entries.sort!((a, b) => a.relPath < b.relPath);

  if (opt.showJson) {
    printJsonOutput(entries, opt);
  } else if (opt.showSummary) {
    printSummaryOutput(entries);
  } else if (opt.showTree) {
    printTreeOutput(entries, opt);
  } else {
    printCategorizedOutput(entries, opt);
  }

  return 0;
}

private:

void printHelp(ref GetoptResult res) {
  defaultGetoptPrinter(
    "Usage: inspect_tree.d [options] [directory/file ...]\n\n"
    ~ "Inspects and categorizes D modules, C wrappers, build configs,"
    ~ " and docs.\n"
    ~ "Defaults to current directory if no targets specified.",
    res.options
  );
}

bool hasPrefix(string s, string prefix) {
  return s.length >= prefix.length && s[0 .. prefix.length] == prefix;
}

bool hasSuffix(string s, string suffix) {
  return s.length >= suffix.length && s[$ - suffix.length .. $] == suffix;
}

bool containsStr(string s, string sub) {
  return s.indexOf(sub) != -1;
}

bool isIgnoredDir(string name, bool includeAll) {
  if (includeAll) {
    return false;
  }
  return name == "_build" || name == ".git" || name == ".dub"
    || name == ".subprojects" || name == ".cache";
}

void scanPath(
  string target,
  ref FileEntry[] entries,
  const ref ScanOptions opt,
  size_t currentDepth
) {
  if (currentDepth > opt.maxDepth) {
    return;
  }

  if (isFile(target)) {
    entries ~= inspectFile(target, target);
    return;
  }

  try {
    foreach (entry; dirEntries(target, SpanMode.shallow)) {
      string base = baseName(entry.name);
      if (entry.isDir) {
        if (!isIgnoredDir(base, opt.includeAll)) {
          scanPath(entry.name, entries, opt, currentDepth + 1);
        }
      } else if (entry.isFile) {
        entries ~= inspectFile(entry.name, entry.name);
      }
    }
  } catch (Exception ex) {
    stderr.writefln("Warning: Cannot read directory %s: %s", target, ex.msg);
  }
}

FileEntry inspectFile(string filePath, string relPath) {
  string normPath = buildNormalizedPath(relPath);
  string base = baseName(normPath);
  string ext = extension(normPath);

  FileEntry entry;
  entry.path = filePath;
  entry.relPath = normPath;

  if (ext == ".d") {
    inspectDModule(entry);
  } else if (ext == ".c" || ext == ".h" || ext == ".cpp" || ext == ".hpp") {
    inspectCFile(entry, ext, base);
  } else if (isBuildFile(base, ext)) {
    inspectBuildFile(entry, base);
  } else if (isDocFile(ext)) {
    inspectDocFile(entry, ext);
  } else {
    entry.category = FileCategory.other;
    entry.subCategory = ext.length > 1 ? ext[1 .. $] : "file";
  }

  return entry;
}

bool isBuildFile(string base, string ext) {
  return base == "meson.build" || base == "meson.options"
    || base == "meson_options.txt" || base == "dub.json"
    || base == "dub.sdl" || ext == ".wrap";
}

bool isDocFile(string ext) {
  return ext == ".md" || ext == ".txt" || ext == ".rst" || ext == ".adoc";
}

void inspectDModule(ref FileEntry entry) {
  entry.category = FileCategory.dModule;
  string base = baseName(entry.relPath);

  if (base == "package.d") {
    entry.subCategory = "package facade";
  } else if (containsStr(entry.relPath, "/internal/")
    || hasPrefix(entry.relPath, "internal/")) {
    entry.subCategory = "internal";
  } else if (hasSuffix(base, "_test.d") || containsStr(entry.relPath, "/test/")
    || containsStr(entry.relPath, "/tests/")) {
    entry.subCategory = "test";
  } else {
    entry.subCategory = "module";
  }

  try {
    string content = readText(entry.path);
    entry.lineCount = countLines(content);
    entry.identifier = extractDModuleName(content, entry.relPath);
  } catch (Exception) {
    entry.identifier = defaultModuleName(entry.relPath);
  }
}

void inspectCFile(ref FileEntry entry, string ext, string base) {
  entry.category = FileCategory.cFile;

  if (ext == ".h" || ext == ".hpp") {
    entry.subCategory = "header";
  } else if (hasSuffix(base, "_test.c")
    || containsStr(entry.relPath, "/test/")) {
    entry.subCategory = "test";
  } else {
    entry.subCategory = "source";
  }

  try {
    string content = readText(entry.path);
    entry.lineCount = countLines(content);
  } catch (Exception) {
    entry.lineCount = 0;
  }
}

void inspectBuildFile(ref FileEntry entry, string base) {
  entry.category = FileCategory.buildConfig;

  if (base == "meson.build") {
    entry.subCategory = "meson.build";
  } else if (hasPrefix(base, "meson")) {
    entry.subCategory = "meson options";
  } else if (hasSuffix(base, ".wrap")) {
    entry.subCategory = "wrap subproject";
  } else if (hasPrefix(base, "dub.")) {
    entry.subCategory = "dub manifest";
  } else {
    entry.subCategory = "build";
  }

  try {
    string content = readText(entry.path);
    entry.lineCount = countLines(content);
    entry.identifier = extractBuildIdentifier(content, base);
  } catch (Exception) {
    entry.identifier = "";
  }
}

void inspectDocFile(ref FileEntry entry, string ext) {
  entry.category = FileCategory.doc;
  entry.subCategory = ext == ".md" ? "markdown" : "doc";

  try {
    string content = readText(entry.path);
    entry.lineCount = countLines(content);
    entry.identifier = extractDocTitle(content);
  } catch (Exception) {
    entry.identifier = "";
  }
}

size_t countLines(string content) {
  size_t count = 0;
  foreach (char c; content) {
    if (c == '\n') {
      count++;
    }
  }
  return count > 0 || content.length > 0 ? count + 1 : 0;
}

string extractDModuleName(string content, string relPath) {
  string[] lines = content.splitLines();
  foreach (string line; lines) {
    string trimmed = line.strip();
    if (trimmed.length == 0 || hasPrefix(trimmed, "//")
      || hasPrefix(trimmed, "/*") || hasPrefix(trimmed, "*")
      || hasPrefix(trimmed, "#!")) {
      continue;
    }
    if (hasPrefix(trimmed, "module ") && hasSuffix(trimmed, ";")) {
      return trimmed[7 .. $ - 1].strip();
    }
    if (!hasPrefix(trimmed, "/") && !hasPrefix(trimmed, "*")) {
      break;
    }
  }
  return defaultModuleName(relPath);
}

string defaultModuleName(string relPath) {
  string norm = buildNormalizedPath(relPath);
  if (hasSuffix(norm, ".d")) {
    norm = norm[0 .. $ - 2];
  }
  return norm.replace("/", ".");
}

string extractBuildIdentifier(string content, string base) {
  if (base == "meson.build") {
    foreach (line; content.splitLines()) {
      string t = line.strip();
      if (hasPrefix(t, "project(")) {
        size_t q1 = t.indexOf('\'');
        if (q1 != -1) {
          size_t q2 = t.indexOf('\'', q1 + 1);
          if (q2 != -1) {
            return "project: " ~ t[q1 + 1 .. q2];
          }
        }
      }
    }
  }
  return "";
}

string extractDocTitle(string content) {
  foreach (line; content.splitLines()) {
    string t = line.strip();
    if (hasPrefix(t, "# ")) {
      return t[2 .. $].strip();
    }
  }
  return "";
}

bool shouldDisplay(const ref FileEntry entry, const ref ScanOptions opt) {
  bool hasFilter = opt.showDModules || opt.showCFiles
    || opt.showBuildConfigs || opt.showDocs;

  if (!hasFilter) {
    return entry.category != FileCategory.other || opt.includeAll;
  }

  if (opt.showDModules && entry.category == FileCategory.dModule) {
    return true;
  }
  if (opt.showCFiles && entry.category == FileCategory.cFile) {
    return true;
  }
  if (opt.showBuildConfigs && entry.category == FileCategory.buildConfig) {
    return true;
  }
  if (opt.showDocs && entry.category == FileCategory.doc) {
    return true;
  }
  return false;
}

void printCategorizedOutput(
  const ref FileEntry[] entries,
  const ref ScanOptions opt
) {
  FileEntry[] dMods;
  FileEntry[] cFiles;
  FileEntry[] bConfigs;
  FileEntry[] docs;

  foreach (ref const entry; entries) {
    if (!shouldDisplay(entry, opt)) {
      continue;
    }
    final switch (entry.category) {
      case FileCategory.dModule:
        dMods ~= cast(FileEntry) entry;
        break;
      case FileCategory.cFile:
        cFiles ~= cast(FileEntry) entry;
        break;
      case FileCategory.buildConfig:
        bConfigs ~= cast(FileEntry) entry;
        break;
      case FileCategory.doc:
        docs ~= cast(FileEntry) entry;
        break;
      case FileCategory.other:
        break;
    }
  }

  printSection("D Modules", dMods, true);
  printSection("C/C++ Files", cFiles, false);
  printSection("Build Configurations", bConfigs, false);
  printSection("Documentation", docs, false);
}

void printSection(string title, const ref FileEntry[] items, bool showId) {
  if (items.length == 0) {
    return;
  }
  writefln("=== %s (%d) ===", title, items.length);
  foreach (ref const it; items) {
    string info = it.subCategory;
    if (it.identifier.length > 0) {
      info ~= ": " ~ it.identifier;
    }
    if (it.lineCount > 0) {
      info ~= ", " ~ to!string(it.lineCount) ~ " lines";
    }
    writefln("  %-42s [%s]", it.relPath, info);
  }
  writeln();
}

void printSummaryOutput(const ref FileEntry[] entries) {
  size_t dCount = 0;
  size_t cCount = 0;
  size_t bCount = 0;
  size_t docCount = 0;
  size_t otherCount = 0;

  foreach (ref const e; entries) {
    final switch (e.category) {
      case FileCategory.dModule:
        dCount++;
        break;
      case FileCategory.cFile:
        cCount++;
        break;
      case FileCategory.buildConfig:
        bCount++;
        break;
      case FileCategory.doc:
        docCount++;
        break;
      case FileCategory.other:
        otherCount++;
        break;
    }
  }

  writeln("=== Project Tree Summary ===");
  writefln("  D Modules:             %4d", dCount);
  writefln("  C/C++ Files:           %4d", cCount);
  writefln("  Build Configurations:  %4d", bCount);
  writefln("  Documentation Files:   %4d", docCount);
  writefln("  Other Files:           %4d", otherCount);
  writefln("  Total Scanned Files:   %4d", entries.length);
}

void printTreeOutput(
  const ref FileEntry[] entries,
  const ref ScanOptions opt
) {
  foreach (ref const entry; entries) {
    if (!shouldDisplay(entry, opt)) {
      continue;
    }
    string tag = "";
    if (entry.category == FileCategory.dModule) {
      tag = " (D: " ~ entry.identifier ~ ")";
    } else if (entry.category == FileCategory.cFile) {
      tag = " (C: " ~ entry.subCategory ~ ")";
    } else if (entry.category == FileCategory.buildConfig) {
      tag = " (Build: " ~ entry.subCategory ~ ")";
    } else if (entry.category == FileCategory.doc) {
      tag = " (Doc: " ~ entry.subCategory ~ ")";
    }
    writefln("%s%s", entry.relPath, tag);
  }
}

void printJsonOutput(
  const ref FileEntry[] entries,
  const ref ScanOptions opt
) {
  writeln("[");
  bool first = true;
  foreach (ref const entry; entries) {
    if (!shouldDisplay(entry, opt)) {
      continue;
    }
    if (!first) {
      writeln(",");
    }
    first = false;
    writefln(
      "  {\"path\": \"%s\", \"category\": \"%s\", \"subCategory\": \"%s\""
      ~ ", \"identifier\": \"%s\", \"lines\": %d}",
      entry.relPath, to!string(entry.category), entry.subCategory,
      escapeJson(entry.identifier), entry.lineCount
    );
  }
  writeln("\n]");
}

string escapeJson(string s) {
  return s.replace("\\", "\\\\").replace("\"", "\\\"");
}
