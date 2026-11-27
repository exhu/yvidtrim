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
 *  - GLES only via glad2.gles2; no D import of C sources or headers
 *  - Controllers never import App/Window or create their View
 *  - Every module with unittest blocks is listed by a Meson file
 *  - No version (unittest) main() outside test_main.d
 */
module check_boundaries;

import std.array : appender, replace;
import std.ascii : isAlphaNum, isWhite;
import std.file : dirEntries, exists, isDir, isFile, readText, SpanMode;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : baseName, dirName, extension;
import std.stdio : stderr, writeln, writefln;
import std.string : endsWith, splitLines, startsWith, strip;
import std.typecons : Nullable, nullable;

enum BoundaryViolationType {
  yguilibIndependence,
  internalPublicSymbol,
  umbrellaRootImport,
  publicImportReexport,
  singleModulePackageDir,
  directCImport,
  docLineLimit,
  glesImport,
  controllerIsolation,
  testTargetCoverage,
  unittestMain
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

  import std.algorithm : canFind;

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

  import std.algorithm : canFind;
  import std.regex : ctRegex, matchFirst;

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
  import std.algorithm : canFind;
  import std.regex : ctRegex, matchFirst;

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

  import std.algorithm : canFind;

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
 * Returns the index just past the `{ ... }` block whose `{` is at open, or
 * the source length when the block never closes.
 */
size_t braceBlockEnd(string source, size_t open) {
  int depth = 0;
  size_t p = open;
  while (p < source.length) {
    const size_t next = skipNonCode(source, p);
    if (next > p) {
      p = next;
      continue;
    }
    if (source[p] == '{') {
      depth++;
    } else if (source[p] == '}') {
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
 * Returns the index just past a `unittest { ... }` block starting at start,
 * or start when no such block begins there.
 */
size_t unittestBlockEnd(string source, size_t start) {
  enum keyword = "unittest";
  const bool wordStart = start == 0 || !isIdentChar(source[start - 1]);
  if (!wordStart || !startsAt(source, start, keyword)) {
    return start;
  }
  const size_t p = skipSpaces(source, start + keyword.length);
  if (p >= source.length || source[p] != '{') {
    return start;
  }
  return braceBlockEnd(source, p);
}

/**
 * Returns source with every `unittest { ... }` block blanked out. Newlines
 * are kept so reported line numbers stay correct.
 */
string codeWithoutUnittests(string source) {
  auto code = appender!string();
  size_t pos = 0;
  while (pos < source.length) {
    const size_t blockEnd = unittestBlockEnd(source, pos);
    if (blockEnd > pos) {
      foreach (char c; source[pos .. blockEnd]) {
        if (c == '\n') {
          code.put('\n');
        }
      }
      pos = blockEnd;
      continue;
    }
    const size_t skipEnd = skipNonCode(source, pos);
    if (skipEnd > pos) {
      code.put(source[pos .. skipEnd]);
      pos = skipEnd;
      continue;
    }
    code.put(source[pos]);
    pos++;
  }
  return code.data;
}

unittest {
  // Nested braces, a brace inside a string and inside comments are skipped.
  string src = "void a() {}\n"
    ~ "unittest {\n"
    ~ "  if (true) { writeln(\"}\"); } // }\n"
    ~ "  /+ { +/\n"
    ~ "}\n"
    ~ "// unittest { kept\n"
    ~ "int b; /* { */\n";
  assert(codeWithoutUnittests(src) == "void a() {}\n"
    ~ "\n\n\n\n"
    ~ "// unittest { kept\n"
    ~ "int b; /* { */\n");
}

/**
 * Returns true when content has a `unittest { ... }` block outside comments
 * and string literals. Every block removes at least its keyword and braces
 * from codeWithoutUnittests, so the lengths differ exactly when one exists.
 */
bool hasUnittestBlock(string content) {
  return codeWithoutUnittests(content).length != content.length;
}

/**
 * Returns the index just past `version (unittest)` starting at pos, or pos
 * when no such condition begins there. Spacing is optional.
 */
size_t versionUnittestEnd(string source, size_t pos) {
  const bool wordStart = pos == 0 || !isIdentChar(source[pos - 1]);
  if (!wordStart || !startsAt(source, pos, "version")) {
    return pos;
  }
  size_t p = skipSpaces(source, pos + "version".length);
  if (p >= source.length || source[p] != '(') {
    return pos;
  }
  p = skipSpaces(source, p + 1);
  if (!startsAt(source, p, "unittest")) {
    return pos;
  }
  p = skipSpaces(source, p + "unittest".length);
  if (p >= source.length || source[p] != ')') {
    return pos;
  }
  return p + 1;
}

/**
 * Returns true when source between from and to calls or declares `main(`
 * outside comments and string literals.
 */
bool hasMainDeclaration(string source, size_t from, size_t to) {
  size_t p = from;
  while (p < to) {
    const size_t next = skipNonCode(source, p);
    if (next > p) {
      p = next;
      continue;
    }
    const bool wordStart = p == 0 || !isIdentChar(source[p - 1]);
    if (wordStart && startsAt(source, p, "main")) {
      const size_t q = skipSpaces(source, p + "main".length);
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
 * Returns the module name of an import declaration on line, or null when the
 * line is not an import.
 */
Nullable!string importedModule(string line) {
  import std.regex : ctRegex, matchFirst;

  auto importRe = ctRegex!(
    r"^\s*(?:(?:public|static|private)\s+)?import\s+([A-Za-z_][\w.]*)"
  );
  auto m = matchFirst(line, importRe);
  if (m.empty) {
    return Nullable!string.init;
  }
  return nullable(m[1]);
}

unittest {
  Nullable!string mod = importedModule("  import glad2.gles2 : GL_BLEND;");
  assert(mod.get == "glad2.gles2");
  assert(importedModule("int import_count;").isNull);
}

bool startsWithAny(string path, string[] prefixes) {
  foreach (prefix; prefixes) {
    if (path.startsWith(prefix)) {
      return true;
    }
  }
  return false;
}

/**
 * Returns the *-clibs directories at the repository root and under yguilib.
 */
string[] findClibsDirs() {
  string[] dirs;
  foreach (root; [".", "yguilib"]) {
    if (!exists(root)) {
      continue;
    }
    foreach (entry; dirEntries(root, SpanMode.shallow)) {
      if (entry.isDir && baseName(entry.name).endsWith("-clibs")) {
        dirs ~= entry.name;
      }
    }
  }
  return dirs;
}

/**
 * Returns true when GLES or OpenGL is imported through a module other than
 * glad2.gles2.
 */
bool isGlesForbidden(string moduleName) {
  if (moduleName == "glad2.gles2") {
    return false;
  }
  return moduleName.startsWith("glad")
    || moduleName.startsWith("bindbc.opengl")
    || moduleName.startsWith("derelict.opengl")
    || moduleName.startsWith("gl.");
}

/**
 * Returns true when moduleName resolves to a `.c` or `.h` file next to dir
 * or in one of clibDirs.
 */
bool isCModule(string dir, string moduleName, string[] clibDirs) {
  const string rel = moduleName.replace(".", "/");
  foreach (base; [dir] ~ clibDirs) {
    foreach (ext; [".c", ".h"]) {
      if (exists(base ~ "/" ~ rel ~ ext)) {
        return true;
      }
    }
  }
  return false;
}

/**
 * Checks that GLES is imported only via glad2.gles2 and that D files never
 * import C sources or headers directly. clibDirs lists the *-clibs dirs.
 */
void checkGlesImports(
  string filePath,
  string content,
  string[] clibDirs,
  ref BoundaryViolation[] violations
) {
  string[] scopes = [
    "yguilib/source/", "source/", "yguilib/examples/", "yguilib/benchmarks/"
  ];
  if (!startsWithAny(filePath, scopes)) {
    return;
  }

  string dir = dirName(filePath);
  string[] lines = content.splitLines();
  foreach (size_t idx, string line; lines) {
    Nullable!string mod = importedModule(line);
    if (mod.isNull) {
      continue;
    }
    if (isGlesForbidden(mod.get)) {
      violations ~= BoundaryViolation(
        filePath,
        idx + 1,
        BoundaryViolationType.glesImport,
        "GLES must be imported only via glad2.gles2: " ~ mod.get
      );
    } else if (isCModule(dir, mod.get, clibDirs)) {
      violations ~= BoundaryViolation(
        filePath,
        idx + 1,
        BoundaryViolationType.directCImport,
        "D code must not import C headers directly; use a D binding: "
        ~ mod.get
      );
    }
  }
}

/**
 * Checks that controllers never import yguilib.app or yguilib.window and
 * never create their own View. unittest blocks are ignored.
 */
void checkControllerIsolation(
  string filePath,
  string content,
  ref BoundaryViolation[] violations
) {
  import std.algorithm : canFind;
  import std.regex : ctRegex, matchFirst;

  if (extension(filePath) != ".d"
    || !baseName(filePath).canFind("controller")) {
    return;
  }
  if (!startsWithAny(filePath, ["source/", "yguilib/examples/"])) {
    return;
  }

  auto viewCreateRe = ctRegex!(r"\bnew\s+\w+View\s*\(");
  string[] lines = codeWithoutUnittests(content).splitLines();
  foreach (size_t idx, string line; lines) {
    string trimmed = line.strip();
    if (trimmed.startsWith("//") || trimmed.startsWith("*")) {
      continue;
    }
    Nullable!string mod = importedModule(line);
    if (!mod.isNull && (mod.get == "yguilib.app"
      || mod.get == "yguilib.window")) {
      violations ~= BoundaryViolation(
        filePath,
        idx + 1,
        BoundaryViolationType.controllerIsolation,
        "Controllers must not import " ~ mod.get ~ ": " ~ trimmed
      );
    }
    if (!matchFirst(line, viewCreateRe).empty) {
      violations ~= BoundaryViolation(
        filePath,
        idx + 1,
        BoundaryViolationType.controllerIsolation,
        "Controllers must not create their View; main() attaches it: "
        ~ trimmed
      );
    }
  }
}

/**
 * A quoted `*.d` path named by a Meson file, resolved relative to the
 * repository root. line is the 1-based line in mesonFile.
 */
struct MesonListedFile {
  string mesonFile;
  size_t line;
  string path;
}

/**
 * Returns the quoted `*.d` paths listed by meson.build and
 * yguilib/meson.build. This is a string match; Meson is not evaluated.
 */
MesonListedFile[] mesonListedDFiles() {
  import std.regex : ctRegex, matchAll;

  auto quotedDRe = ctRegex!(r"'([^'\n]*\.d)'");
  MesonListedFile[] listed;
  foreach (string mesonFile; ["meson.build", "yguilib/meson.build"]) {
    if (!exists(mesonFile)) {
      continue;
    }
    const string dir = dirName(mesonFile);
    string[] lines = readText(mesonFile).splitLines();
    foreach (size_t idx, string line; lines) {
      foreach (m; matchAll(line, quotedDRe)) {
        const string rel = m[1];
        listed ~= MesonListedFile(
          mesonFile,
          idx + 1,
          dir == "." ? rel : dir ~ "/" ~ rel
        );
      }
    }
  }
  return listed;
}

/**
 * Returns true when path appears in listed.
 */
bool isListedPath(MesonListedFile[] listed, string path) {
  foreach (const ref entry; listed) {
    if (entry.path == path) {
      return true;
    }
  }
  return false;
}

/**
 * Checks that every module with a unittest block under yguilib/source,
 * yguilib/examples, yguilib/benchmarks, or source/ is listed by a Meson file.
 */
void checkTestTargetCoverage(
  MesonListedFile[] listed,
  ref BoundaryViolation[] violations
) {
  string[] roots = [
    "yguilib/source", "yguilib/examples", "yguilib/benchmarks", "source"
  ];
  foreach (root; roots) {
    if (!exists(root)) {
      continue;
    }
    foreach (entry; dirEntries(root, SpanMode.depth)) {
      if (!entry.isFile || extension(entry.name) != ".d") {
        continue;
      }
      const string content = readText(entry.name);
      if (!hasUnittestBlock(content) || isListedPath(listed, entry.name)) {
        continue;
      }
      violations ~= BoundaryViolation(
        entry.name,
        1,
        BoundaryViolationType.testTargetCoverage,
        "Module has unittest blocks but no Meson test target lists it; add "
        ~ "it to meson.build or yguilib/meson.build."
      );
    }
  }
}

/**
 * Warns when a Meson file lists a `*.d` path that does not exist on disk.
 */
void checkMesonPathsExist(
  MesonListedFile[] listed,
  ref BoundaryViolation[] warnings
) {
  foreach (const ref entry; listed) {
    if (!exists(entry.path)) {
      warnings ~= BoundaryViolation(
        entry.mesonFile,
        entry.line,
        BoundaryViolationType.testTargetCoverage,
        "Meson lists a missing file: " ~ entry.path
      );
    }
  }
}

/**
 * Checks that no `version (unittest)` block declares main() outside
 * test_main.d. Both the braced form and a single-line declaration are
 * matched; comments and string literals are ignored.
 */
void checkNoUnittestMain(
  string filePath,
  string content,
  ref BoundaryViolation[] violations
) {
  if (extension(filePath) != ".d" || baseName(filePath) == "test_main.d") {
    return;
  }
  size_t p = 0;
  while (p < content.length) {
    const size_t condEnd = versionUnittestEnd(content, p);
    if (condEnd == p) {
      const size_t skipEnd = skipNonCode(content, p);
      p = skipEnd > p ? skipEnd : p + 1;
      continue;
    }
    const size_t from = skipSpaces(content, condEnd);
    const bool braced = from < content.length && content[from] == '{';
    const size_t to = braced
      ? braceBlockEnd(content, from)
      : indexPast(content, condEnd, "\n");
    if (hasMainDeclaration(content, from, to)) {
      violations ~= BoundaryViolation(
        filePath,
        lineNumberAt(content, p),
        BoundaryViolationType.unittestMain,
        "version (unittest) must not declare main(); use test_main.d."
      );
    }
    p = condEnd;
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
      ~ "Rules:\n"
      ~ "  1 yguilib independence\n"
      ~ "  2 internal/ encapsulation (no public symbols)\n"
      ~ "  3 no umbrella package.d or public import re-exports\n"
      ~ "  4 package directory rule\n"
      ~ "  5 no direct D import of C sources or headers (use clibs/)\n"
      ~ "  6 ARCHITECTURE.md size limit\n"
      ~ "  7 GLES only via glad2.gles2\n"
      ~ "  8 controllers never import App/Window or create their View\n"
      ~ "  9 unittest modules are listed by a Meson file\n"
      ~ "  10 no version (unittest) main() outside test_main.d\n\n"
      ~ "Options:",
      helpInfo.options
    );
    return 0;
  }

  BoundaryViolation[] violations;
  BoundaryViolation[] warnings;

  // 1. Root package umbrella check
  checkRootPackageUmbrellas(violations);

  // 2. Scan all files in project
  string[] clibDirs = findClibsDirs();
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
            checkGlesImports(entry.name, content, clibDirs, violations);
            checkControllerIsolation(entry.name, content, violations);
            checkNoUnittestMain(entry.name, content, violations);
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

  // 5. Meson test target coverage (warnings do not fail the run)
  MesonListedFile[] listedFiles = mesonListedDFiles();
  checkTestTargetCoverage(listedFiles, violations);
  checkMesonPathsExist(listedFiles, warnings);

  // Print results
  if (warnings.length > 0) {
    foreach (const ref w; warnings) {
      writefln("%s:%d: [boundary warning] %s", w.file, w.line, w.message);
    }
    writefln("Total boundary warnings: %d", warnings.length);
  }
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
