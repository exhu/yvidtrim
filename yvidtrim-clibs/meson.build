
dependencies = [
]

sources = [
  'yvidtrim_sdl3.c',
]

yvidtrim_sdl3_lib = static_library(
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
  link_with : yvidtrim_sdl3_lib,
)
test('yvidtrim_sdl3', test_exe)

yvidtrim_sdl3_dep = declare_dependency(
  link_with : yvidtrim_sdl3_lib,
  include_directories : include_directories('.'),
  dependencies : dependencies,
)
