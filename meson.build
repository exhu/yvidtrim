project(
  'yvidtrim',
  ['d', 'c'],
  version : '0.1',
  meson_version : '>= 1.3.0',
  default_options : ['warning_level=3'],
)

subdir('glad2gles31')

glad2_inc = include_directories('source')
glad2_src = files(
  'source/glad2/gles2.d',
  'source/glad2/khrplatform.d',
)

subdir('yguilib')
subdir('yvidtrim-clibs')

yvidtrim_src = files(
  'source/yvidtrim/app.d',
  'source/yvidtrim/clibs/sdl3.d',
)

src = glad2_src + yguilib_src + yvidtrim_src

executable('yvidtrim',
           src,
           link_with : [yvidtrim_sdl3_lib, yguilib_sdl3_lib, glad_lib],
           d_import_dirs : ['source', 'yguilib/source'],
           include_directories : ['source', 'yguilib/source'])

