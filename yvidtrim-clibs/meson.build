
dependencies = [
]

sources = [
  'yvidtrim_sdl3.c',
]

lib = static_library(
  'yvidtrim_sdl3',
  sources,
  install : false,
  gnu_symbol_visibility : 'hidden',
  dependencies : dependencies,
)

test_exe = executable(
  'yvidtrim_sdl3_test',
  'yvidtrim_sdl3_test.c',
  dependencies : dependencies,
  link_with : lib,
)
test('yvidtrim_sdl3', test_exe)
