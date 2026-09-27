module yguilib.widget.internal.layout_dimension;

package(yguilib):
import std.algorithm.comparison : max, min;
import yguilib.widget.layout_components : Dimension, SizingMode;

/// Resolves a dimension according to its sizing mode.
float resolveDimension(
  const Dimension dim,
  float currentVal,
  float contentDim,
  float padBorder,
  float minVal
) {
  switch (dim.mode) {
  case SizingMode.fixed:
    return dim.value;
  case SizingMode.auto_:
    return contentDim + padBorder;
  case SizingMode.fraction:
    return minVal;
  default:
    return currentVal;
  }
}

/// Clamps val to [minVal, maxVal] and to >= 0.
float clampDimension(
  float val,
  float minVal,
  float maxVal
) {
  if (val > maxVal) {
    val = maxVal;
  }
  if (val < minVal) {
    val = minVal;
  }
  if (val < 0.0f) {
    val = 0.0f;
  }
  return val;
}

/// Full pipeline: resolve then clamp.
float computeDimension(
  const Dimension dim,
  float currentVal,
  float contentDim,
  float padBorder,
  float minVal,
  float maxVal
) {
  const float resolved = resolveDimension(
    dim,
    currentVal,
    contentDim,
    padBorder,
    minVal
  );
  return clampDimension(resolved, minVal, maxVal);
}

unittest {
  // resolveDimension
  assert(resolveDimension(
    Dimension(50.0f, SizingMode.fixed), 10.0f, 20.0f, 5.0f, 15.0f
  ) == 50.0f);
  assert(resolveDimension(
    Dimension(0.0f, SizingMode.auto_), 10.0f, 20.0f, 5.0f, 15.0f
  ) == 25.0f);
  assert(resolveDimension(
    Dimension(1.0f, SizingMode.fraction), 10.0f, 20.0f, 5.0f, 15.0f
  ) == 15.0f);

  // clampDimension
  assert(clampDimension(120.0f, 10.0f, 100.0f) == 100.0f);
  assert(clampDimension(5.0f, 10.0f, 100.0f) == 10.0f);
  assert(clampDimension(-5.0f, -20.0f, 100.0f) == 0.0f);

  // computeDimension
  assert(computeDimension(
    Dimension(150.0f, SizingMode.fixed), 0.0f, 0.0f, 0.0f, 20.0f, 100.0f
  ) == 100.0f);
  assert(computeDimension(
    Dimension(10.0f, SizingMode.fixed), 0.0f, 0.0f, 0.0f, 20.0f, 100.0f
  ) == 20.0f);
}
