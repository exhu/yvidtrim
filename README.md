# yvidtrim
Video trimming tool

## How to build
dub.json is used only for code completion, use meson+ninja to build:
```
meson setup _build .
ninja -C _build
```

## Dependencies
The project depends on external C and C++ libraries, e.g. SDL3,
ffmpeg, however full C bindings for D are not used, and not generated.
Instead private C libraries are built as part of the project which are
in "yvidtrim-clibs" and "yguilib-clibs" directories. They wrap C/C++
dependencies by exporting custom functions that do a meaningful minimal work
to be called from D code. Third party types and constants if necessary are
defined as opaque. The private libraries (wrappers) hide away external
api details, so that D code is dependent only on those opaque custom
wrappers. This allows to consume any new version of the C/C++
dependencies and helps to catch errors early and have LSP support when
updating and editing the related C code.

## Wrapper C libraries
Each wrapper library uses only one C/C++ third-party library and is named
following the pattern "<project>_LIBRARY_NAME", e.g. for sdl3 it will be
"yvidtrim_sdl3" or "yguilib_sdl3".

Each wrapper C library's public interface bindings are declared in a
corresponding D module in "./source/<project>/clibs/"
e.g. "./source/yvidtrim/clibs/sdl3.d" for "./yvidtrim-clibs/yvidtrim_sdl3.h",
or "./source/yguilib/clibs/sdl3.d" for "./yguilib-clibs/yguilib_sdl3.h".

Each public symbol in a wrapper library is prefixed with the library name,
e.g. "yvidtrim_sdl3_" for "yvidtrim_sdl3" library, or "yguilib_sdl3_" for
"yguilib_sdl3".

This is why meson is used to build D code as well as the wrappers.

## yguilib
./source/yguilib is an independent GUI library that uses SDL3 (via
yguilib-clibs). Sources in ./source/yguilib/ and ./yguilib-clibs/ must not
depend on ./source/yvidtrim or ./yvidtrim-clibs.
