#!/usr/bin/env rdmd
/**
 * Entry point for renaming types, symbols, and modules.
 */
module rename;

import std.stdio : stderr, writeln;

import rename_module : runModuleRename;
import rename_symbol : runSymbolRename;
import rename_type : runTypeRename;

enum usage = "Usage: rdmd rename.d <type|symbol|module> [options] <Old> <New>\n"
  ~ "Dry-run by default; pass --apply to write.\n"
  ~ "Run 'rdmd rename.d <mode> --help' for the options of a mode.";

int main(string[] args) {
  const string mode = args.length > 1 ? args[1] : "";
  if (mode == "-h" || mode == "--help") {
    writeln(usage);
    return 0;
  }
  // The mode name takes the place of argv[0] for the mode's getopt.
  switch (mode) {
    case "type":
      return runTypeRename(args[1 .. $]);
    case "symbol":
      return runSymbolRename(args[1 .. $]);
    case "module":
      return runModuleRename(args[1 .. $]);
    default:
      stderr.writeln(usage);
      return 2;
  }
}
