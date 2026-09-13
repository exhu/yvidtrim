dependencies = [
  dependency('sdl3'),
]

sources = [
  'yguilib_sdl3.c',
]

yguilib_sdl3_lib = static_library(
  'yguilib_sdl3',
  sources,
  install : false,
  gnu_symbol_visibility : 'hidden',
  dependencies : dependencies,
)

test_exe = executable(
  'yguilib_sdl3_test',
  'yguilib_sdl3_test.c',
  dependencies : dependencies,
  link_with : yguilib_sdl3_lib,
)
test('yguilib_sdl3', test_exe)

yguilib_sdl3_dep = declare_dependency(
  link_with : yguilib_sdl3_lib,
  include_directories : include_directories('.'),
  dependencies : dependencies,
)
