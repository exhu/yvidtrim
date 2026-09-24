subdir('yguilib-clibs')

glad2gles31d_dep = dependency('glad2gles31d')

yguilib_inc = include_directories('source')
yguilib_assets_inc = include_directories('assets')

yguilib_src = files(
  'source/yguilib/app.d',
  'source/yguilib/assets.d',
  'source/yguilib/clibs/sdl3.d',
  'source/yguilib/clibs/sdl3_ttf.d',
  'source/yguilib/controller/internal/controller_stack.d',
  'source/yguilib/controller/package.d',
  'source/yguilib/events/internal/message_bus.d',
  'source/yguilib/events/internal/sdl_events.d',
  'source/yguilib/events/keyboard.d',
  'source/yguilib/events/package.d',
  'source/yguilib/internal/assets.d',
  'source/yguilib/internal/logger.d',
  'source/yguilib/model.d',
  'source/yguilib/render/font.d',
  'source/yguilib/render/internal/clip_stack.d',
  'source/yguilib/render/internal/gl_util.d',
  'source/yguilib/render/internal/pipelines.d',
  'source/yguilib/render/internal/text_cache.d',
  'source/yguilib/render/package.d',
  'source/yguilib/render/render_types.d',
  'source/yguilib/uisystem.d',
  'source/yguilib/widget/component.d',
  'source/yguilib/widget/internal/widget_painter.d',
  'source/yguilib/widget/layout.d',
  'source/yguilib/widget/package.d',
  'source/yguilib/window.d',
)

yguilib_deps = [yguilib_sdl3_dep, yguilib_sdl3_ttf_dep, glad2gles31d_dep]

yguilib_lib = static_library(
  'yguilib',
  yguilib_src,
  include_directories : yguilib_inc,
  d_import_dirs : [yguilib_inc, yguilib_assets_inc],
  dependencies : yguilib_deps,
  install : false,
)

yguilib_dep = declare_dependency(
  link_with : yguilib_lib,
  include_directories : yguilib_inc,
  d_import_dirs : [yguilib_inc, yguilib_assets_inc],
  dependencies : yguilib_deps,
)

yguilib_test_src = yguilib_src + files(
  'source/yguilib/internal/test_main.d',
)

yguilib_test_exe = executable(
  'yguilib_test',
  yguilib_test_src,
  d_unittest : true,
  include_directories : yguilib_inc,
  d_import_dirs : [yguilib_inc, yguilib_assets_inc],
  dependencies : yguilib_deps,
)
test('yguilib_test', yguilib_test_exe)
