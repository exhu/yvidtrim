project(
  'yvidtrim',
  'd',
  version : '0.1',
  meson_version : '>= 1.3.0',
  default_options : ['warning_level=3'],
)

subdir('yvidtrim-clibs')

src = ['sources/yvidtrim/app.d']

executable('yvidtrim', src, link_with: yvidtrim_sdl3)
