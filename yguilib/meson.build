subdir('yguilib-clibs')

glad2gles31d_dep = dependency('glad2gles31d')

yguilib_inc = include_directories('source')
yguilib_assets_inc = include_directories('assets')

# Peak texture/heap telemetry (version MemTelemetry): on for debug builds
# by default, see the memtelemetry option.
memtel_opt = get_option('memtelemetry')
yguilib_d_versions = []
if memtel_opt == 'enabled' or (memtel_opt == 'auto' and get_option('debug'))
  yguilib_d_versions += ['MemTelemetry']
endif

yguilib_src = files(
  'source/yguilib/allochelpers.d',
  'source/yguilib/app.d',
  'source/yguilib/assets.d',
  'source/yguilib/clibs/sdl3.d',
  'source/yguilib/clibs/sdl3_image.d',
  'source/yguilib/clibs/sdl3_ttf.d',
  'source/yguilib/controller/internal/controller_stack.d',
  'source/yguilib/controller/package.d',
  'source/yguilib/controls/button.d',
  'source/yguilib/controls/common.d',
  'source/yguilib/controls/composite_view.d',
  'source/yguilib/controls/hover_button_system.d',
  'source/yguilib/controls/internal/axis.d',
  'source/yguilib/controls/internal/button_support.d',
  'source/yguilib/controls/scrollbars.d',
  'source/yguilib/controls/tabcontrol.d',
  'source/yguilib/controls/testing.d',
  'source/yguilib/controls/tooltip.d',
  'source/yguilib/controls/virtlist.d',
  'source/yguilib/events/builder.d',
  'source/yguilib/events/internal/message_bus.d',
  'source/yguilib/events/internal/sdl_events.d',
  'source/yguilib/events/keyboard.d',
  'source/yguilib/events/package.d',
  'source/yguilib/internal/assets.d',
  'source/yguilib/internal/logger.d',
  'source/yguilib/internal/memstats.d',
  'source/yguilib/internal/timer_service.d',
  'source/yguilib/internal/uisystem_impl.d',
  'source/yguilib/internal/uisystem_controller.d',
  'source/yguilib/model.d',
  'source/yguilib/object_registry.d',
  'source/yguilib/render/canvas/package.d',
  'source/yguilib/render/canvas/package_test.d',
  'source/yguilib/render/canvas/path2d.d',
  'source/yguilib/render/canvas/types.d',
  'source/yguilib/render/font.d',
  'source/yguilib/render/font_manager.d',
  'source/yguilib/render/image.d',
  'source/yguilib/render/internal/clip_stack.d',
  'source/yguilib/render/internal/gl_test_util.d',
  'source/yguilib/render/internal/gl_util.d',
  'source/yguilib/render/internal/glyph_atlas.d',
  'source/yguilib/render/internal/offscreen.d',
  'source/yguilib/render/internal/path_flatten.d',
  'source/yguilib/render/internal/path_stroker.d',
  'source/yguilib/render/internal/pipelines.d',
  'source/yguilib/render/internal/stencil_ops.d',
  'source/yguilib/render/internal/svg_path_parser.d',
  'source/yguilib/render/internal/text_batch.d',
  'source/yguilib/render/internal/text_cache.d',
  'source/yguilib/render/package.d',
  'source/yguilib/render/render_target.d',
  'source/yguilib/render/render_types.d',
  'source/yguilib/render/texture.d',
  'source/yguilib/serhelpers.d',
  'source/yguilib/texthelpers.d',
  'source/yguilib/timercontrol.d',
  'source/yguilib/timers.d',
  'source/yguilib/uisystem.d',
  'source/yguilib/widget/builder.d',
  'source/yguilib/widget/component.d',
  'source/yguilib/widget/data_components.d',
  'source/yguilib/widget/drawing_components.d',
  'source/yguilib/widget/input_components.d',
  'source/yguilib/widget/internal/collect_visible.d',
  'source/yguilib/widget/internal/data_system.d',
  'source/yguilib/widget/internal/debug_draw_system.d',
  'source/yguilib/widget/internal/input_system.d',
  'source/yguilib/widget/internal/focus_system.d',
  'source/yguilib/widget/internal/layout_anchor.d',
  'source/yguilib/widget/internal/layout_axis.d',
  'source/yguilib/widget/internal/layout_content_size.d',
  'source/yguilib/widget/internal/layout_dimension.d',
  'source/yguilib/widget/internal/layout_flex.d',
  'source/yguilib/widget/internal/layout_system.d',
  'source/yguilib/widget/internal/layout_text.d',
  'source/yguilib/widget/internal/scroll_system.d',
  'source/yguilib/widget/internal/system_pipeline.d',
  'source/yguilib/widget/internal/text_label_cache.d',
  'source/yguilib/widget/internal/virtlist_system.d',
  'source/yguilib/widget/internal/widget_painter.d',
  'source/yguilib/widget/layout_components.d',
  'source/yguilib/widget/package.d',
  'source/yguilib/widget/scroll_components.d',
  'source/yguilib/widget/system.d',
  'source/yguilib/widget/test_fixture.d',
  'source/yguilib/widget/virtlist_components.d',
  'source/yguilib/widget/visible.d',
  'source/yguilib/widget/widget_view.d',
  'source/yguilib/window.d',
)

yguilib_deps = [
  yguilib_sdl3_dep,
  yguilib_sdl3_ttf_dep,
  yguilib_sdl3_image_dep,
  glad2gles31d_dep,
]

yguilib_lib = static_library(
  'yguilib',
  yguilib_src,
  include_directories : yguilib_inc,
  d_import_dirs : [yguilib_inc, yguilib_assets_inc],
  d_module_versions : yguilib_d_versions,
  dependencies : yguilib_deps,
  install : false,
)

yguilib_dep = declare_dependency(
  link_with : yguilib_lib,
  include_directories : yguilib_inc,
  d_import_dirs : [yguilib_inc, yguilib_assets_inc],
  d_module_versions : yguilib_d_versions,
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
  d_module_versions : yguilib_d_versions,
  dependencies : yguilib_deps,
)
test('yguilib_test', yguilib_test_exe)

helloworld_inc = include_directories('examples')

helloworld_lib_src = files(
  'examples/helloworld/controller.d',
  'examples/helloworld/model.d',
  'examples/helloworld/view.d',
)

helloworld_exe = executable(
  'helloworld',
  helloworld_lib_src + files('examples/helloworld/app.d'),
  include_directories : helloworld_inc,
  d_import_dirs : [yguilib_inc, helloworld_inc],
  dependencies : [yguilib_dep],
)

helloworld_test_exe = executable(
  'helloworld_test',
  helloworld_lib_src + files('source/yguilib/internal/test_main.d'),
  d_unittest : true,
  include_directories : helloworld_inc,
  d_import_dirs : [yguilib_inc, helloworld_inc],
  dependencies : [yguilib_dep],
)
test('helloworld_test', helloworld_test_exe)

# Benchmarks are built only on request:
#   meson setup _build --reconfigure -Dbenchmarks=true
if get_option('benchmarks')
  textbench_exe = executable(
    'textbench',
    files('benchmarks/textbench/app.d'),
    d_import_dirs : [yguilib_inc],
    dependencies : [yguilib_dep],
  )
endif
