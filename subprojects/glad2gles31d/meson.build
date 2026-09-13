project(
  'glad2gles31d',
  'd',
  version : '0.1',
  meson_version : '>= 1.3.0',
  default_options : ['warning_level=3'],
)

glad_c_dep = dependency('glad2gles31')

glad2gles31d_inc = include_directories('source')
glad2gles31d_src = files(
  'source/glad2/gles2.d',
  'source/glad2/khrplatform.d',
)

glad2gles31d_lib = static_library(
  'glad2gles31d',
  glad2gles31d_src,
  include_directories : glad2gles31d_inc,
  d_import_dirs : glad2gles31d_inc,
  dependencies : [glad_c_dep],
  install : false,
)

glad2gles31d_dep = declare_dependency(
  link_with : glad2gles31d_lib,
  include_directories : glad2gles31d_inc,
  d_import_dirs : glad2gles31d_inc,
  dependencies : [glad_c_dep],
)

# Registers this dependency globally with Meson so consumers (like yguilib)
# can simply write `dependency('glad2gles31d')` without needing explicit
# fallback variable specifications like `fallback : ['glad2gles31d', 'glad2gles31d_dep']`.
meson.override_dependency('glad2gles31d', glad2gles31d_dep)

test_exe = executable(
  'glad2gles31d_test',
  'test/test_glad.d',
  dependencies : [glad2gles31d_dep],
)
test('glad2gles31d', test_exe)

