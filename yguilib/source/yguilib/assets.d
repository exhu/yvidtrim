/// All public assets, e.g. default font go there.
module yguilib.assets;

/// default font data, public because expected to be used by library consumers.
enum string defaultTtfFontData =
  import("yguilib/fonts/GoogleSansCode-Regular.ttf");
