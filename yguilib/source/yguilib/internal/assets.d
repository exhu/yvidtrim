/// assets of implementation details of the rendering pipeline
/// or other systems belong to this package
module yguilib.internal.assets;

package(yguilib):
/**
 * Common start of every vertex shader: `#version` (must come first) and
 * the shared `logicToClip` helper. Vertex shader files omit `#version`.
 */
enum string vertPrelude = "#version 300 es\n"
  ~ import("yguilib/shaders/common/logic_to_clip.glsl");

enum string colorVertexShaderSource =
  vertPrelude ~ import("yguilib/shaders/color.vert.glsl");
enum string colorFragmentShaderSource =
  import("yguilib/shaders/color.frag.glsl");

enum string texVertexShaderSource =
  vertPrelude ~ import("yguilib/shaders/texture.vert.glsl");
enum string texFragmentShaderSource =
  import("yguilib/shaders/texture.frag.glsl");

enum string rrVertexShaderSource =
  vertPrelude ~ import("yguilib/shaders/roundrect.vert.glsl");
enum string rrFragmentShaderSource =
  import("yguilib/shaders/roundrect.frag.glsl");

enum string paintVertexShaderSource =
  vertPrelude ~ import("yguilib/shaders/paint.vert.glsl");
enum string paintFragmentShaderSource =
  import("yguilib/shaders/paint.frag.glsl");

enum string blurFragmentShaderSource =
  import("yguilib/shaders/blur.frag.glsl");

enum string patternFragmentShaderSource =
  import("yguilib/shaders/pattern.frag.glsl");

/// Vertex shader of the alpha-masked gradient/pattern program variants.
enum string paintMaskVertexShaderSource =
  vertPrelude ~ import("yguilib/shaders/paint_mask.vert.glsl");

/**
 * `fragSource` with `#define MASK 1` after its `#version` line, selecting
 * the alpha-mask variant of `paint.frag.glsl` and `pattern.frag.glsl`.
 */
enum string withMaskDefine(string fragSource) =
  "#version 300 es\n#define MASK 1\n"
  ~ fragSource["#version 300 es\n".length .. $];
