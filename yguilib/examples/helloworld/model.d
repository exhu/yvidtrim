module helloworld.model;

import colors = yguilib.render.colors;
import yguilib.model : VersionedModel;
import yguilib.render.render_types : ColorF;

/// Palette cycled when the color button is pressed.
immutable ColorF[] helloTextPalette = [
  colors.brightWhite,
  colors.brightCyan,
  colors.yellow,
  colors.brightGreen,
  colors.brightMagenta,
  colors.brightRed,
];

/// Versioned state for the Hello World example app.
final class HelloModel : VersionedModel {
public:
  size_t colorIndex = 0;

  ColorF currentColor() const {
    return helloTextPalette[colorIndex % helloTextPalette.length];
  }
}
