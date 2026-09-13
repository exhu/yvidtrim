/// Helper script to scaffold a private C wrapper and D bindings.
module scaffold;

import std.algorithm : canFind, all;
import std.ascii : isAlphaNum, isLower;
import std.file : exists, mkdirRecurse, write;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : buildPath, dirName;
import std.stdio : stderr, writefln, writeln;
import std.string : format, toUpper;

struct Config {
  string proj;
  string libName;
  string depName;
  bool force = false;
  bool dryRun = false;
}

int main(string[] args) {
  Config cfg;

  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "dep", "Meson pkg-config dependency name (e.g. sdl3-ttf)", &cfg.depName,
      "force|f", "Overwrite existing files", &cfg.force,
      "dry-run|n", "Print actions without writing files", &cfg.dryRun,
    );
  } catch (Exception e) {
    stderr.writefln("Error: %s", e.msg);
    return 1;
  }

  if (helpInfo.helpWanted || args.length < 3) {
    writeln("Usage: rdmd scaffold.d [options] <proj> <libname>");
    writeln("Scaffolds private C wrapper and D binding files.\n");
    writeln("Arguments:");
    writeln("  <proj>     Target project: 'yvidtrim' or 'yguilib'");
    writeln("  <libname>  Target library name (e.g. 'sdl3_ttf', 'ffmpeg')\n");
    defaultGetoptPrinter("Options:", helpInfo.options);
    return helpInfo.helpWanted ? 0 : 1;
  }

  cfg.proj = args[1];
  cfg.libName = args[2];

  if (cfg.proj != "yvidtrim" && cfg.proj != "yguilib") {
    stderr.writefln(
      "Error: <proj> must be 'yvidtrim' or 'yguilib', got '%s'",
      cfg.proj,
    );
    return 1;
  }

  if (!isValidLibName(cfg.libName)) {
    stderr.writefln(
      "Error: <libname> '%s' must contain only lowercase letters, " ~
      "numbers, and underscores.",
      cfg.libName,
    );
    return 1;
  }

  if (cfg.depName.length == 0) {
    cfg.depName = cfg.libName;
  }

  return runScaffold(cfg);
}

bool isValidLibName(string name) {
  if (name.length == 0) return false;
  return name.all!(c => isLower(c) || isAlphaNum(c) || c == '_');
}

int runScaffold(const ref Config cfg) {
  string prefix = format("%s_%s", cfg.proj, cfg.libName);
  string cDir;
  string dDir;

  if (cfg.proj == "yguilib") {
    if (exists("yguilib-clibs")) {
      cDir = "yguilib-clibs";
      dDir = buildPath("source", "yguilib", "clibs");
    } else {
      cDir = buildPath("yguilib", "yguilib-clibs");
      dDir = buildPath("yguilib", "source", "yguilib", "clibs");
    }
  } else {
    cDir = format("%s-clibs", cfg.proj);
    dDir = buildPath("source", cfg.proj, "clibs");
  }

  string cHeader = buildPath(cDir, prefix ~ ".h");
  string cSource = buildPath(cDir, prefix ~ ".c");
  string cTest = buildPath(cDir, prefix ~ "_test.c");
  string dModule = buildPath(dDir, cfg.libName ~ ".d");

  struct FileTemplate {
    string path;
    string content;
  }

  FileTemplate[] files = [
    FileTemplate(cHeader, generateCHeader(prefix)),
    FileTemplate(cSource, generateCSource(prefix)),
    FileTemplate(cTest, generateCTest(prefix)),
    FileTemplate(dModule, generateDBinding(cfg.proj, cfg.libName, prefix)),
  ];

  // Check for existing files
  if (!cfg.force) {
    foreach (f; files) {
      if (exists(f.path)) {
        stderr.writefln(
          "Error: file '%s' already exists. Use --force to overwrite.",
          f.path,
        );
        return 1;
      }
    }
  }

  foreach (f; files) {
    if (cfg.dryRun) {
      writefln("[dry-run] Would write %s", f.path);
    } else {
      mkdirRecurse(dirName(f.path));
      write(f.path, f.content);
      writefln("Created %s", f.path);
    }
  }

  printMesonInstructions(cfg, prefix, cDir);
  return 0;
}

string generateCHeader(string prefix) {
  return format(
    "#pragma once\n\n" ~
    "#ifdef __cplusplus\n" ~
    "extern \"C\" {\n" ~
    "#endif\n\n" ~
    "/**\n" ~
    " * Sample hello function for %s wrapper.\n" ~
    " */\n" ~
    "int %s_hello(void);\n\n" ~
    "#ifdef __cplusplus\n" ~
    "}\n" ~
    "#endif\n",
    prefix,
    prefix,
  );
}

string generateCSource(string prefix) {
  return format(
    "#include \"%s.h\"\n\n" ~
    "int %s_hello(void) {\n" ~
    "  return 0;\n" ~
    "}\n",
    prefix,
    prefix,
  );
}

string generateCTest(string prefix) {
  return format(
    "#include \"%s.h\"\n" ~
    "#include <stdio.h>\n\n" ~
    "int main(int argc, char **argv) {\n" ~
    "  if (argc != 1) {\n" ~
    "    printf(\"%%s takes no arguments.\\n\", argv[0]);\n" ~
    "    return 1;\n" ~
    "  }\n" ~
    "  return %s_hello();\n" ~
    "}\n",
    prefix,
    prefix,
  );
}

string generateDBinding(string proj, string libName, string prefix) {
  return format(
    "/// Bindings to %s-clibs %s C wrapper\n" ~
    "module %s.clibs.%s;\n\n" ~
    "extern(C) {\n" ~
    "  int %s_hello();\n" ~
    "}\n",
    proj,
    libName,
    proj,
    libName,
    prefix,
  );
}

void printMesonInstructions(
  const ref Config cfg,
  string prefix,
  string cDir,
) {
  string libTarget = prefix ~ "_lib";
  string testExe = prefix ~ "_test";

  writefln("\n=== Next Steps ===");
  writefln("1. Add the static library and test in %s/meson.build:", cDir);
  writeln("------------------------------------------------------------");
  writefln(
    "dep_%s = dependency('%s')\n\n" ~
    "%s = static_library(\n" ~
    "  '%s',\n" ~
    "  ['%s.c'],\n" ~
    "  install : false,\n" ~
    "  gnu_symbol_visibility : 'hidden',\n" ~
    "  dependencies : [dep_%s],\n" ~
    ")\n\n" ~
    "%s = executable(\n" ~
    "  '%s',\n" ~
    "  '%s_test.c',\n" ~
    "  dependencies : [dep_%s],\n" ~
    "  link_with : %s,\n" ~
    ")\n" ~
    "test('%s', %s)",
    cfg.libName,
    cfg.depName,
    libTarget,
    prefix,
    prefix,
    cfg.libName,
    testExe,
    testExe,
    prefix,
    cfg.libName,
    libTarget,
    prefix,
    testExe,
  );
  writeln("------------------------------------------------------------");
  if (cfg.proj == "yguilib") {
    writefln(
      "2. Add 'source/yguilib/clibs/%s.d' to yguilib_src in yguilib/meson.build.",
      cfg.libName,
    );
    writefln(
      "3. Link '%s' into yguilib_test in yguilib/meson.build " ~
      "(and root meson.build if used by yvidtrim).",
      libTarget,
    );
  } else {
    writefln(
      "2. Add 'source/%s/clibs/%s.d' to %s_src in root meson.build.",
      cfg.proj,
      cfg.libName,
      cfg.proj,
    );
    writefln("3. Link '%s' into executable in root meson.build.", libTarget);
  }
  writeln("4. Run verification:");
  writeln("   meson setup _build --reconfigure && " ~
    "ninja -C _build && meson test -C _build");
}
