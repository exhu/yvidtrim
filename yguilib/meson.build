subdir('yguilib-clibs')

glad2gles31d_dep = dependency('glad2gles31d')

yguilib_inc = include_directories('source')
yguilib_assets_inc = include_directories('assets')

yguilib_src = files(
  'source/yguilib/app.d',
  'source/yguilib/clibs/sdl3.d',
  'source/yguilib/controller.d',
  'source/yguilib/events.d',
  'source/yguilib/logger.d',
  'source/yguilib/model.d',
  'source/yguilib/render.d',
  'source/yguilib/render_types.d',
  'source/yguilib/uisystem.d',
  'source/yguilib/widget.d',
  'source/yguilib/window.d',
)

yguilib_lib = static_library(
  'yguilib',
  yguilib_src,
  include_directories : yguilib_inc,
  d_import_dirs : [yguilib_inc, yguilib_assets_inc],
  dependencies : [yguilib_sdl3_dep, glad2gles31d_dep],
  install : false,
)

yguilib_dep = declare_dependency(
  link_with : yguilib_lib,
  include_directories : yguilib_inc,
  d_import_dirs : [yguilib_inc, yguilib_assets_inc],
  dependencies : [yguilib_sdl3_dep, glad2gles31d_dep],
)

yguilib_test_src = yguilib_src + files(
  'source/yguilib/test_main.d',
)

yguilib_test_exe = executable(
  'yguilib_test',
  yguilib_test_src,
  d_unittest : true,
  include_directories : yguilib_inc,
  d_import_dirs : [yguilib_inc, yguilib_assets_inc],
  dependencies : [yguilib_sdl3_dep, glad2gles31d_dep],
)
test('yguilib_test', yguilib_test_exe)

