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

dep_sdl3_ttf = dependency('sdl3-ttf')
ttf_dependencies = [dependencies, dep_sdl3_ttf]

yguilib_sdl3_ttf_lib = static_library(
  'yguilib_sdl3_ttf',
  ['yguilib_sdl3_ttf.c'],
  install : false,
  gnu_symbol_visibility : 'hidden',
  dependencies : ttf_dependencies,
)

font_rel_path = 'yguilib/assets/yguilib/fonts/GoogleSansCode-Regular.ttf'
font_path = meson.project_source_root() / font_rel_path

yguilib_sdl3_ttf_test_exe = executable(
  'yguilib_sdl3_ttf_test',
  'yguilib_sdl3_ttf_test.c',
  c_args : ['-DFONT_PATH="' + font_path + '"'],
  dependencies : ttf_dependencies,
  link_with : yguilib_sdl3_ttf_lib,
)
test('yguilib_sdl3_ttf', yguilib_sdl3_ttf_test_exe)

yguilib_sdl3_ttf_dep = declare_dependency(
  link_with : yguilib_sdl3_ttf_lib,
  include_directories : include_directories('.'),
  dependencies : ttf_dependencies,
)


dep_sdl3_image = dependency('sdl3-image')
image_dependencies = [dependencies, dep_sdl3_image]

yguilib_sdl3_image_lib = static_library(
  'yguilib_sdl3_image',
  ['yguilib_sdl3_image.c'],
  install : false,
  gnu_symbol_visibility : 'hidden',
  dependencies : image_dependencies,
)

yguilib_sdl3_image_test_exe = executable(
  'yguilib_sdl3_image_test',
  'yguilib_sdl3_image_test.c',
  dependencies : image_dependencies,
  link_with : yguilib_sdl3_image_lib,
)
test('yguilib_sdl3_image', yguilib_sdl3_image_test_exe)

yguilib_sdl3_image_dep = declare_dependency(
  link_with : yguilib_sdl3_image_lib,
  include_directories : include_directories('.'),
  dependencies : image_dependencies,
)
