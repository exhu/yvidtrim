project(
  'glad2gles31',
  'c',
  version : '0.1',
  meson_version : '>= 1.3.0',
  default_options : ['warning_level=3'],
)

glad_inc = include_directories('include')

egl_dep = dependency('egl', required : false)

glad_lib = static_library(
  'glad',
  'src/gles2.c',
  include_directories : glad_inc,
  c_args : ['-DGLAD_GLES2_USE_SYSTEM_EGL'],
  dependencies : [egl_dep],
  install : false,
)

glad_dep = declare_dependency(
  link_with : glad_lib,
  include_directories : glad_inc,
  dependencies : [egl_dep],
)

# Registers this dependency globally with Meson so glad2gles31d can simply
# write `dependency('glad2gles31')`.
meson.override_dependency('glad2gles31', glad_dep)

