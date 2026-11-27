module yguilib.widget.internal.layout_dimension;

package(yguilib):
import std.math.traits : isFinite;
import yguilib.widget.layout_components : Dimension, SizingMode;

/// Parameters for `computeDimension`.
struct DimensionParams {
  Dimension dim;
  float currentVal = 0.0f;
  float contentDim = 0.0f;
  float padBorder = 0.0f;
  float minVal = 0.0f;
  float maxVal = float.infinity;

  ref DimensionParams withDim(Dimension dim) return {
    this.dim = dim;
    return this;
  }

  ref DimensionParams withCurrentVal(float currentVal) return {
    this.currentVal = currentVal;
    return this;
  }

  ref DimensionParams withContentDim(float contentDim) return {
    this.contentDim = contentDim;
    return this;
  }

  ref DimensionParams withPadBorder(float padBorder) return {
    this.padBorder = padBorder;
    return this;
  }

  ref DimensionParams withMinVal(float minVal) return {
    this.minVal = minVal;
    return this;
  }

  ref DimensionParams withMaxVal(float maxVal) return {
    this.maxVal = maxVal;
    return this;
  }
}

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

/// Clamps val to [minVal, maxVal] and to >= 0, sanitizing non-finite values.
float clampDimension(
  float val,
  float minVal,
  float maxVal
) {
  if (!isFinite(val)) {
    val = 0.0f;
  }
  if (isFinite(maxVal) && val > maxVal) {
    val = maxVal;
  }
  if (isFinite(minVal) && val < minVal) {
    val = minVal;
  }
  if (val < 0.0f) {
    val = 0.0f;
  }
  return val;
}

/// Full pipeline: resolve then clamp.
float computeDimension(in DimensionParams params) {
  const float resolved = resolveDimension(
    params.dim,
    params.currentVal,
    params.contentDim,
    params.padBorder,
    params.minVal
  );
  return clampDimension(resolved, params.minVal, params.maxVal);
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
  assert(clampDimension(float.nan, 10.0f, 100.0f) == 10.0f);
  assert(clampDimension(float.infinity, 0.0f, float.infinity) == 0.0f);
  assert(clampDimension(-float.infinity, 10.0f, 100.0f) == 10.0f);

  // computeDimension
  DimensionParams p1;
  p1.withDim(Dimension(150.0f, SizingMode.fixed))
    .withMinVal(20.0f)
    .withMaxVal(100.0f);
  assert(computeDimension(p1) == 100.0f);

  DimensionParams p2;
  p2.withDim(Dimension(10.0f, SizingMode.fixed))
    .withMinVal(20.0f)
    .withMaxVal(100.0f);
  assert(computeDimension(p2) == 20.0f);
}
