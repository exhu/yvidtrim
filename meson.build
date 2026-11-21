project(
  'yvidtrim',
  ['d', 'c'],
  version : '0.1',
  meson_version : '>= 1.3.0',
  default_options : ['warning_level=3'],
)

subdir('yguilib')
subdir('yvidtrim-clibs')

yvidtrim_lib_src = files(
  'source/yvidtrim/clibs/sdl3.d',
  'source/yvidtrim/controller.d',
  'source/yvidtrim/model.d',
  'source/yvidtrim/uitree/mainview.d',
  'source/yvidtrim/view.d',
)

yvidtrim_src = yvidtrim_lib_src + files(
  'source/yvidtrim/app.d',
)

yvidtrim_inc = include_directories('source')

executable(
  'yvidtrim',
  yvidtrim_src,
  include_directories : yvidtrim_inc,
  d_import_dirs : yvidtrim_inc,
  dependencies : [yguilib_dep, yvidtrim_sdl3_dep],
)

yvidtrim_test_exe = executable(
  'yvidtrim_test',
  yvidtrim_lib_src + files('source/yvidtrim/test_main.d'),
  d_unittest : true,
  include_directories : yvidtrim_inc,
  d_import_dirs : yvidtrim_inc,
  dependencies : [yguilib_dep, yvidtrim_sdl3_dep],
)
test('yvidtrim_test', yvidtrim_test_exe)

guidemo_lib_src = files(
  'source/guidemo/common.d',
  'source/guidemo/controller.d',
  'source/guidemo/demo_model_helpers.d',
  'source/guidemo/hover_button.d',
  'source/guidemo/hover_button_system.d',
  'source/guidemo/model.d',
  'source/guidemo/pages/button_controller.d',
  'source/guidemo/pages/button_page.d',
  'source/guidemo/pages/button_system_controller.d',
  'source/guidemo/pages/button_system_page.d',
  'source/guidemo/pages/layout_painter_controller.d',
  'source/guidemo/pages/layout_painter_page.d',
  'source/guidemo/pages/scrollbars_controller.d',
  'source/guidemo/pages/scrollbars_page.d',
  'source/guidemo/pages/tabcontrol_controller.d',
  'source/guidemo/pages/tabcontrol_page.d',
  'source/guidemo/pages/textlabel_controller.d',
  'source/guidemo/pages/textlabel_page.d',
  'source/guidemo/scrollbars.d',
  'source/guidemo/tab_button.d',
  'source/guidemo/tabcontrol.d',
  'source/guidemo/view.d',
)

guidemo_src = guidemo_lib_src + files(
  'source/guidemo/guidemoapp.d',
)

executable(
  'guidemo',
  guidemo_src,
  include_directories : yvidtrim_inc,
  d_import_dirs : yvidtrim_inc,
  dependencies : [yguilib_dep],
)

guidemo_test_exe = executable(
  'guidemo_test',
  guidemo_lib_src + files('source/guidemo/test_main.d'),
  d_unittest : true,
  include_directories : yvidtrim_inc,
  d_import_dirs : yvidtrim_inc,
  dependencies : [yguilib_dep],
)
test('guidemo_test', guidemo_test_exe)

hover_button_test_exe = executable(
  'hover_button_test',
  files('source/guidemo/hover_button.d', 'source/guidemo/test_main.d'),
  d_unittest : true,
  include_directories : yvidtrim_inc,
  d_import_dirs : yvidtrim_inc,
  dependencies : [yguilib_dep],
)
test('hover_button_test', hover_button_test_exe)

hover_button_system_test_exe = executable(
  'hover_button_system_test',
  files('source/guidemo/hover_button_system.d', 'source/guidemo/test_main.d'),
  d_unittest : true,
  include_directories : yvidtrim_inc,
  d_import_dirs : yvidtrim_inc,
  dependencies : [yguilib_dep],
)
test('hover_button_system_test', hover_button_system_test_exe)

tab_button_test_exe = executable(
  'tab_button_test',
  files(
    'source/guidemo/tab_button.d',
    'source/guidemo/model.d',
    'source/guidemo/test_main.d',
  ),
  d_unittest : true,
  include_directories : yvidtrim_inc,
  d_import_dirs : yvidtrim_inc,
  dependencies : [yguilib_dep],
)
test('tab_button_test', tab_button_test_exe)

tabcontrol_test_exe = executable(
  'tabcontrol_test',
  files('source/guidemo/tabcontrol.d', 'source/guidemo/test_main.d'),
  d_unittest : true,
  include_directories : yvidtrim_inc,
  d_import_dirs : yvidtrim_inc,
  dependencies : [yguilib_dep],
)
test('tabcontrol_test', tabcontrol_test_exe)

scrollbars_test_exe = executable(
  'scrollbars_test',
  files('source/guidemo/scrollbars.d', 'source/guidemo/test_main.d'),
  d_unittest : true,
  include_directories : yvidtrim_inc,
  d_import_dirs : yvidtrim_inc,
  dependencies : [yguilib_dep],
)
test('scrollbars_test', scrollbars_test_exe)


