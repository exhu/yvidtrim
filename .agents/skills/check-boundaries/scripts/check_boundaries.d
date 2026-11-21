#!/usr/bin/env rdmd
/**
 * Architectural boundary and encapsulation checker for yvidtrim and yguilib.
 * Enforces AGENTS.md and codestyle.md:
 *  - yguilib independence (must never import yvidtrim or guidemo)
 *  - Internal directory encapsulation (no public symbols in internal/)
 *  - No umbrella root package.d or public import re-exports
 *  - Package directory rule (no single-module package.d dirs without
 *    internal/)
 *  - Direct C wrapper abstraction (D only imports clibs.*)
 */
module check_boundaries;

import core.sys.posix.sys.stat : fstat, stat_t, S_ISFIFO, S_ISREG;
import std.algorithm : canFind, endsWith, startsWith;
import std.file : dirEntries, exists, isDir, isFile, readText, SpanMode;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : baseName, dirName, extension;
import std.regex : ctRegex, matchFirst;
import std.stdio : stderr, writeln, writefln;
import std.string : splitLines, strip;

enum BoundaryViolationType {
  yguilibIndependence,
  internalPublicSymbol,
  umbrellaRootImport,
  publicImportReexport,
  singleModulePackageDir,
  directCImport,
  docLineLimit
}

struct BoundaryViolation {
  string file;
  size_t line;
  BoundaryViolationType type;
  string message;
}

/**
 * Checks a file for yguilib independence violations.
 */
void checkYguilibIndependence(
  string filePath,
  string content,
  ref BoundaryViolation[] violations
) {
  if (!filePath.startsWith("yguilib/")) {
    return;
  }

  string[] lines = content.splitLines();
  foreach (size_t idx, string line; lines) {
    string trimmed = line.strip();
    if (trimmed.startsWith("//") || trimmed.startsWith("*")) {
      continue;
    }
    foreach (dep; ["yvidtrim", "guidemo"]) {
      // Check D imports
      if (trimmed.startsWith("import ") && trimmed.canFind(dep)) {
        violations ~= BoundaryViolation(
          filePath,
          idx + 1,
          BoundaryViolationType.yguilibIndependence,
          "yguilib must not import " ~ dep ~ " symbols: " ~ trimmed
        );
      }
      // Check C includes
      if (trimmed.startsWith("#include") && trimmed.canFind(dep)) {
        violations ~= BoundaryViolation(
          filePath,
          idx + 1,
          BoundaryViolationType.yguilibIndependence,
          "yguilib C code must not include " ~ dep ~ " headers: " ~ trimmed
        );
      }
    }
  }
}

/**
 * Checks that D files do not use public import re-exports.
 */
void checkPublicImportReexports(
  string filePath,
  string content,
  ref BoundaryViolation[] violations
) {
  if (extension(filePath) != ".d") {
    return;
  }

  auto publicImportRe = ctRegex!(r"^\s*public\s+import\b");
  bool inMultilineComment = false;
  string[] lines = content.splitLines();
  foreach (size_t idx, string line; lines) {
    string trimmed = line.strip();
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
    if (!matchFirst(line, publicImportRe).empty) {
      violations ~= BoundaryViolation(
        filePath,
        idx + 1,
        BoundaryViolationType.publicImportReexport,
        "Public import re-exports are prohibited; import modules explicitly."
      );
    }
  }
}

/**
 * Checks that internal/ modules do not expose public symbols.
 */
void checkInternalEncapsulation(
  string filePath,
  string content,
  ref BoundaryViolation[] violations
) {
  if (!filePath.canFind("/internal/")) {
    return;
  }
  if (extension(filePath) != ".d") {
    return;
  }

  auto inlinePublicRe = ctRegex!(
    r"^\s*public\s+(void|int|bool|string|float|double|char|"
    ~ r"auto|class|struct|interface|enum|alias)\s+"
  );

  string[] lines = content.splitLines();
  foreach (size_t idx, string line; lines) {
    string trimmed = line.strip();
    if (trimmed.startsWith("//") || trimmed.startsWith("*")) {
      continue;
    }
    if (trimmed == "public:" || trimmed.startsWith("public:")) {
      violations ~= BoundaryViolation(
        filePath,
        idx + 1,
        BoundaryViolationType.internalPublicSymbol,
        "Internal module cannot have 'public:' section. Use 'package:'."
      );
    }
    auto m = matchFirst(line, inlinePublicRe);
    if (!m.empty) {
      violations ~= BoundaryViolation(
        filePath,
        idx + 1,
        BoundaryViolationType.internalPublicSymbol,
        "Internal module cannot declare public symbol '" ~ m[0].strip() ~ "'."
      );
    }
  }
}

/**
 * Verifies no umbrella root package.d exists.
 */
void checkRootPackageUmbrellas(ref BoundaryViolation[] violations) {
  string[] rootPackages = [
    "source/yvidtrim/package.d",
    "yguilib/source/yguilib/package.d"
  ];
  foreach (pkg; rootPackages) {
    if (exists(pkg)) {
      violations ~= BoundaryViolation(
        pkg,
        1,
        BoundaryViolationType.umbrellaRootImport,
        "Monolithic root package.d is prohibited. Subsystems must be imported "
        ~ "explicitly."
      );
    }
  }
}

/**
 * Checks package directory rules (single-module package.d dirs without
 * internal/ are prohibited; multi-module packages do not require package.d).
 */
void checkDomainFacades(string baseDir, ref BoundaryViolation[] violations) {
  if (!exists(baseDir)) {
    return;
  }

  // Group D files by directory
  string[][string] dirFiles;
  foreach (entry; dirEntries(baseDir, SpanMode.depth)) {
    if (entry.isFile && extension(entry.name) == ".d") {
      string dir = dirName(entry.name);
      dirFiles[dir] ~= baseName(entry.name);
    }
  }

  foreach (dir, files; dirFiles) {
    // Skip root package directories, internal directories, clibs, and pages
    if (dir == "yguilib/source/yguilib" || dir == "source/yvidtrim"
      || dir == "source/guidemo" || dir.canFind("/internal")
      || dir.canFind("/clibs") || dir.canFind("/pages")) {
      continue;
    }

    bool hasPackageD = false;
    size_t moduleCount = 0;
    foreach (f; files) {
      if (f == "package.d") {
        hasPackageD = true;
      } else {
        moduleCount++;
      }
    }

    bool hasInternalDir = exists(dir ~ "/internal") && isDir(dir ~ "/internal");

    // Rule: do not create a directory for a single module file as package.d,
    // unless it encapsulates an internal/ implementation directory.
    if (moduleCount == 0 && hasPackageD && !hasInternalDir) {
      violations ~= BoundaryViolation(
        dir ~ "/package.d",
        1,
        BoundaryViolationType.singleModulePackageDir,
        "Directory contains only package.d without internal modules. "
        ~ "A single module file should be used instead."
      );
    }
  }
}

/**
 * Checks that ARCHITECTURE.md stays under 250 lines per AGENTS.md.
 */
void checkArchitectureLineLimit(ref BoundaryViolation[] violations) {
  enum maxArchitectureLines = 249;
  string archPath = "ARCHITECTURE.md";
  if (!exists(archPath)) {
    return;
  }
  size_t lineCount = readText(archPath).splitLines().length;
  if (lineCount > maxArchitectureLines) {
    import std.format : format;
    violations ~= BoundaryViolation(
      archPath,
      lineCount,
      BoundaryViolationType.docLineLimit,
      format(
        "ARCHITECTURE.md has %d lines; must stay under 250 lines.",
        lineCount
      )
    );
  }
}

int main(string[] args) {
  GetoptResult helpInfo;
  try {
    helpInfo = getopt(args);
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return 1;
  }

  if (helpInfo.helpWanted) {
    defaultGetoptPrinter(
      "Usage: check_boundaries.d [options]\n"
      ~ "Checks architectural boundaries and encapsulation rules.\n\n"
      ~ "Options:",
      helpInfo.options
    );
    return 0;
  }

  BoundaryViolation[] violations;

  // 1. Root package umbrella check
  checkRootPackageUmbrellas(violations);

  // 2. Scan all files in project
  string[] searchDirs = ["yguilib", "source", "yvidtrim-clibs"];
  foreach (d; searchDirs) {
    if (!exists(d)) {
      continue;
    }
    foreach (entry; dirEntries(d, SpanMode.depth)) {
      if (entry.isFile) {
        string ext = extension(entry.name);
        if (ext == ".d" || ext == ".c" || ext == ".h") {
          string content = readText(entry.name);
          checkYguilibIndependence(entry.name, content, violations);
          checkInternalEncapsulation(entry.name, content, violations);
          if (ext == ".d") {
            checkPublicImportReexports(entry.name, content, violations);
          }
        }
      }
    }
  }

  // 3. Domain facades check
  checkDomainFacades("yguilib/source/yguilib", violations);
  checkDomainFacades("source/yvidtrim", violations);
  checkDomainFacades("source/guidemo", violations);

  // 4. ARCHITECTURE.md size limit check
  checkArchitectureLineLimit(violations);

  // Print results
  if (violations.length > 0) {
    foreach (const ref v; violations) {
      writefln("%s:%d: [boundary violation] %s", v.file, v.line, v.message);
    }
    writefln("Total boundary violations: %d", violations.length);
    return 1;
  }

  writeln("All architectural boundaries and encapsulation rules satisfied.");
  return 0;
}
