/**
 * assets.d - Embedded guidemo resources (string imports from `assets/`).
 */
module guidemo.assets;

/// 64x64 RGBA PNG: green/blue gradient with a red top-left square, a white
/// top-right bar and a yellow upward triangle (shows orientation).
immutable ubyte[] sampleImagePng =
  cast(immutable ubyte[]) import("guidemo/images/sample.png");
