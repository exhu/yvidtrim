/// Text formatting helpers.
module yguilib.texthelpers;

/// Formats a byte count as B, KiB or MiB, whichever reads best.
string formatBytes(ulong n) {
  import std.format : format;
  enum ulong kib = 1024;
  enum ulong mib = 1024 * 1024;
  if (n < kib) {
    return format("%d B", n);
  }
  if (n < mib) {
    return format("%.2f KiB", n / cast(double) kib);
  }
  return format("%.2f MiB", n / cast(double) mib);
}

unittest {
  assert(formatBytes(0) == "0 B");
  assert(formatBytes(1023) == "1023 B");
  assert(formatBytes(1024) == "1.00 KiB");
  assert(formatBytes(1536) == "1.50 KiB");
  assert(formatBytes(1024 * 1024 - 1) == "1024.00 KiB");
  assert(formatBytes(1024 * 1024) == "1.00 MiB");
  assert(formatBytes(3 * 1024 * 1024 / 2) == "1.50 MiB");
}
