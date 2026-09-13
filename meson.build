project(
  'yvidtrim',
  ['d', 'c'],
  version : '0.1',
  meson_version : '>= 1.3.0',
  default_options : ['warning_level=3'],
)

subdir('yguilib')
subdir('yvidtrim-clibs')

yvidtrim_src = files(
  'source/yvidtrim/app.d',
  'source/yvidtrim/clibs/sdl3.d',
)

yvidtrim_inc = include_directories('source')

executable(
  'yvidtrim',
  yvidtrim_src,
  include_directories : yvidtrim_inc,
  d_import_dirs : yvidtrim_inc,
  dependencies : [yguilib_dep, yvidtrim_sdl3_dep],
)

