#!/usr/bin/env rdmd
/**
 * Asset management and string import manager for yvidtrim and yguilib.
 * Enforces codestyle.md:
 *  - Asset directory structure: assets/<package_name>/...
 *  - Generates and verifies string import declarations in internal/assets.d
 *  - Confirms Meson d_import_dirs configuration
 */
module manage_assets;

import std.algorithm : canFind, endsWith, startsWith;
import std.conv : to;
import std.file : dirEntries, exists, isDir, isFile, readText, SpanMode, write;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : baseName, buildPath, dirName, extension, relativePath;
import std.regex : ctRegex, matchAll, matchFirst;
import std.stdio : stderr, writeln, writefln;
import std.string : replace, splitLines, strip;

string toCamelCaseIdentifier(string relPath) {
  // e.g. "shaders/color.vert.glsl" -> "colorVertGlslSource"
  string base = baseName(relPath);
  string id = "";
  bool capNext = false;
  foreach (char c; base) {
    if (c == '.' || c == '_' || c == '-') {
      capNext = true;
    } else {
      if (capNext) {
        if (c >= 'a' && c <= 'z') {
          id ~= cast(char)(c - 32);
        } else {
          id ~= c;
        }
        capNext = false;
      } else {
        id ~= c;
      }
    }
  }
  return id;
}

void checkAssetPlacements(ref size_t errorCount) {
  string[] assetRoots = ["assets", "yguilib/assets"];
  foreach (root; assetRoots) {
    if (!exists(root) || !isDir(root)) {
      continue;
    }
    foreach (entry; dirEntries(root, SpanMode.shallow)) {
      if (entry.isFile) {
        writefln("%s:1: [error] Loose asset file outside package directory. "
          ~ "Assets must be in %s/<package_name>/", entry.name, root);
        errorCount++;
      }
    }
  }
}

void checkStringImports(ref size_t errorCount) {
  string[] assetsFiles = [
    "yguilib/source/yguilib/internal/assets.d",
    "yguilib/source/yguilib/assets.d",
    "source/yvidtrim/internal/assets.d",
    "source/yvidtrim/assets.d"
  ];

  auto importRe = ctRegex!(`import\s*\(\s*"([^"]+)"\s*\)`);

  foreach (af; assetsFiles) {
    if (!exists(af)) {
      continue;
    }
    string content = readText(af);
    foreach (m; matchAll(content, importRe)) {
      string relAsset = m[1];
      // Search for asset in asset roots
      string p1 = buildPath("assets", relAsset);
      string p2 = buildPath("yguilib/assets", relAsset);
      if (!exists(p1) && !exists(p2)) {
        writefln("%s: [error] Imported asset does not exist on disk: %s",
          af, relAsset);
        errorCount++;
      }
    }
  }
}

void checkMesonConfig(ref size_t errorCount) {
  if (exists("yguilib/meson.build")) {
    string mb = readText("yguilib/meson.build");
    if (!mb.canFind("d_import_dirs") || !mb.canFind("assets")) {
      writefln("yguilib/meson.build: [warning] Missing 'assets' in "
        ~ "d_import_dirs.");
    }
  }
}

int generateImports(string pkgName, bool dryRun) {
  string assetDir = null;
  if (exists("assets/" ~ pkgName)) {
    assetDir = "assets/" ~ pkgName;
  } else if (exists("yguilib/assets/" ~ pkgName)) {
    assetDir = "yguilib/assets/" ~ pkgName;
  }

  if (assetDir is null) {
    stderr.writefln("Error: Asset directory for package '%s' not found.",
      pkgName);
    return 1;
  }

  string modName = pkgName == "yguilib"
    ? "yguilib.internal.assets"
    : pkgName ~ ".internal.assets";
  string outContent = "/// Embedded asset string imports for " ~ pkgName ~ "\n"
    ~ "module " ~ modName ~ ";\n\n"
    ~ "package(" ~ pkgName ~ "):\n";

  foreach (entry; dirEntries(assetDir, SpanMode.depth)) {
    if (entry.isFile) {
      string relPath = relativePath(entry.name, dirName(assetDir));
      string varName = toCamelCaseIdentifier(entry.name);
      outContent ~= "enum string " ~ varName ~ "Source =\n  import(\""
        ~ relPath ~ "\");\n\n";
    }
  }

  if (dryRun) {
    writeln("--- Dry Run Output ---");
    writeln(outContent);
    writeln("----------------------");
  } else {
    string targetPath = pkgName == "yguilib"
      ? "yguilib/source/yguilib/internal/assets.d"
      : "source/" ~ pkgName ~ "/internal/assets.d";
    write(targetPath, outContent);
    writefln("Successfully generated string imports in %s", targetPath);
  }
  return 0;
}

int main(string[] args) {
  bool optCheck = false;
  bool optDryRun = false;
  string optGenPkg = null;

  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "check", "Audit asset placement and string import existence", &optCheck,
      "generate", "Generate internal/assets.d for package", &optGenPkg,
      "dry-run", "Preview generation without writing to disk", &optDryRun
    );
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return 1;
  }

  if (helpInfo.helpWanted || (!optCheck && optGenPkg is null)) {
    defaultGetoptPrinter(
      "Usage: manage_assets.d [options]\n"
      ~ "Audits asset structure and manages D string imports.\n\n"
      ~ "Options:",
      helpInfo.options
    );
    return 0;
  }

  if (optCheck) {
    size_t errorCount = 0;
    checkAssetPlacements(errorCount);
    checkStringImports(errorCount);
    checkMesonConfig(errorCount);

    if (errorCount > 0) {
      writefln("Asset audit completed with %d error(s).", errorCount);
      return 1;
    }
    writeln("All asset paths and string import configurations are valid.");
  }

  if (optGenPkg !is null) {
    return generateImports(optGenPkg, optDryRun);
  }

  return 0;
}
