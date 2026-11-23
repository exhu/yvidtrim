/**
 * Maps logic coordinate `p` (origin top-left, y down) in a viewport of
 * logic size `res` to clip space (origin center, y up).
 */
vec4 logicToClip(vec2 p, vec2 res) {
  vec2 zeroToTwo = (p / res) * 2.0;
  return vec4(zeroToTwo.x - 1.0, 1.0 - zeroToTwo.y, 0.0, 1.0);
}
