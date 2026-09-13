project(
  'yvidtrim',
  ['d', 'c'],
  version : '0.1',
  meson_version : '>= 1.3.0',
  default_options : ['warning_level=3'],
)

subdir('glad2gles31')
subdir('yguilib-clibs')
subdir('yvidtrim-clibs')

glad2_src = [
  'source/glad2/gles2.d',
  'source/glad2/khrplatform.d',
]

yguilib_src = [
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
]

src = glad2_src + yguilib_src + [
  'source/yvidtrim/app.d',
  'source/yvidtrim/clibs/sdl3.d',
]

executable('yvidtrim',
           src,
           link_with: [yvidtrim_sdl3_lib, yguilib_sdl3_lib, glad_lib],
           d_import_dirs: ['source'],
           include_directories: ['source'])

yguilib_test_src = yguilib_src + [
  'source/yguilib/test_main.d',
]

yguilib_test_exe = executable(
  'yguilib_test',
  yguilib_test_src,
  d_unittest: true,
  link_with: [yguilib_sdl3_lib, glad_lib],
  d_import_dirs: ['source'],
  include_directories: ['source'],
)
test('yguilib_test', yguilib_test_exe)
