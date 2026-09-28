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

guidemo_src = files(
  'source/guidemo/common.d',
  'source/guidemo/controller.d',
  'source/guidemo/guidemoapp.d',
  'source/guidemo/model.d',
  'source/guidemo/pages/layout_painter_page.d',
  'source/guidemo/pages/textlabel_page.d',
  'source/guidemo/view.d',
)

executable(
  'guidemo',
  guidemo_src,
  include_directories : yvidtrim_inc,
  d_import_dirs : yvidtrim_inc,
  dependencies : [yguilib_dep],
)

