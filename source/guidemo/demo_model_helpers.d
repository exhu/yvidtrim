/**
 * demo_model_helpers.d - Page numbering and status helpers for DemoModel.
 */
module guidemo.demo_model_helpers;

import guidemo.model : DebugDrawMode, DemoModel, DemoPage, demoPages;

/// Returns the total number of demo pages.
size_t pageCount() {
  return demoPages.length;
}

/// Returns true if `page` is the currently active page in `model`.
bool isPageActive(const DemoModel model, DemoPage page) {
  assert(model !is null, "model must not be null");
  return model.activePage == page;
}

/// Formats the page-specific footer status text for `page` with `details`.
string formatPageStatus(DemoPage page, string details) {
  import std.format : format;

  const size_t num = cast(size_t) page + 1;
  const string title = demoPages[page].statusTitle;
  if (details.length == 0) {
    return format("Page %d: %s", num, title);
  }
  return format("Page %d: %s | %s", num, title, details);
}

/// Formats the footer hint line listing global keys, including the current
/// debug draw `mode` cycled by F1.
string formatGlobalHints(DebugDrawMode mode) {
  import std.format : format;

  return format(
    "[Tab/1-%d] Page | [F1] Debug draw: %s | [F12] Screenshot | "
      ~ "[Q/Esc] Quit",
    demoPages.length % 10,
    mode
  );
}

/// Builds header tab captions prefixed with 1-based page numbers.
string[] headerTabNames() {
  import std.format : format;

  string[] names;
  names.reserve(demoPages.length);
  foreach (i, meta; demoPages) {
    names ~= format("[%d] %s", i + 1, meta.tabTitle);
  }
  return names;
}

unittest {
  assert(pageCount() == 10);

  auto m = new DemoModel();
  assert(isPageActive(m, DemoPage.layoutPainter));
  assert(!isPageActive(m, DemoPage.textLabel));

  m.activePage = DemoPage.scrollbars;
  assert(isPageActive(m, DemoPage.scrollbars));

  assert(
    formatPageStatus(DemoPage.button, "Clicks: 3") ==
      "Page 3: Hover Buttons | Clicks: 3"
  );
  assert(
    formatPageStatus(DemoPage.layoutPainter, "") ==
      "Page 1: Layout"
  );
  assert(
    formatGlobalHints(DebugDrawMode.off) ==
      "[Tab/1-0] Page | [F1] Debug draw: off | [F12] Screenshot | "
        ~ "[Q/Esc] Quit"
  );

  auto tabs = headerTabNames();
  assert(tabs.length == 10);
  assert(tabs[0] == "[1] Layout & Paint");
  assert(tabs[5] == "[6] Scrollbars");
  assert(tabs[6] == "[7] VirtList");
  assert(tabs[7] == "[8] Knob (Lock)");
  assert(tabs[8] == "[9] Button");
  assert(tabs[9] == "[10] Canvas");
}
