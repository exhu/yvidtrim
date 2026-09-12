project(
  'yvidtrim',
  ['d', 'c'],
  version : '0.1',
  meson_version : '>= 1.3.0',
  default_options : ['warning_level=3'],
)

subdir('yvidtrim-clibs')
subdir('yguilib-clibs')

src = [
  'source/yvidtrim/app.d',
  'source/yvidtrim/clibs/sdl3.d',
  'source/yguilib/app.d',
  'source/yguilib/clibs/sdl3.d',
  'source/yguilib/controller.d',
  'source/yguilib/events.d',
  'source/yguilib/model.d',
  'source/yguilib/uisystem.d',
  'source/yguilib/widget.d',
]

executable('yvidtrim',
           src,
           link_with: [yvidtrim_sdl3_lib, yguilib_sdl3_lib],
           include_directories: ['source'])

yguilib_test_src = [
  'source/yguilib/test_main.d',
  'source/yguilib/app.d',
  'source/yguilib/clibs/sdl3.d',
  'source/yguilib/controller.d',
  'source/yguilib/events.d',
  'source/yguilib/model.d',
  'source/yguilib/uisystem.d',
  'source/yguilib/widget.d',
]

yguilib_test_exe = executable(
  'yguilib_test',
  yguilib_test_src,
  d_unittest: true,
  link_with: [yguilib_sdl3_lib],
  include_directories: ['source'],
)
test('yguilib_test', yguilib_test_exe)
