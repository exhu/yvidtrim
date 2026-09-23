module yguilib.internal.assets;

package(yguilib):
enum string colorVertexShaderSource =
  import("yguilib/shaders/color.vert.glsl");
enum string colorFragmentShaderSource =
  import("yguilib/shaders/color.frag.glsl");

enum string texVertexShaderSource =
  import("yguilib/shaders/texture.vert.glsl");
enum string texFragmentShaderSource =
  import("yguilib/shaders/texture.frag.glsl");

enum string rrVertexShaderSource =
  import("yguilib/shaders/roundrect.vert.glsl");
enum string rrFragmentShaderSource =
  import("yguilib/shaders/roundrect.frag.glsl");
