/**
 * demo_model_helpers.d - Page numbering and status helpers for DemoModel.
 */
module guidemo.demo_model_helpers;

import guidemo.model : DemoModel, DemoPage, demoPages;

/// Returns the total number of demo pages.
size_t pageCount() {
  return demoPages.length;
}

/// Returns true if `page` is the currently active page in `model`.
bool isPageActive(const DemoModel model, DemoPage page) {
  assert(model !is null, "model must not be null");
  return model.activePage == page;
}

/// Formats the full footer status text for `page` with `details`.
string formatPageStatus(DemoPage page, string details) {
  import std.format : format;

  const size_t total = demoPages.length;
  const size_t num = cast(size_t) page + 1;
  const string title = demoPages[page].statusTitle;
  if (details.length == 0) {
    return format(
      "[Tab/1-%d] Page %d: %s | [Q/Esc] Quit",
      total,
      num,
      title
    );
  }
  return format(
    "[Tab/1-%d] Page %d: %s | %s | [Q/Esc] Quit",
    total,
    num,
    title,
    details
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
  assert(pageCount() == 9);

  auto m = new DemoModel();
  assert(isPageActive(m, DemoPage.layoutPainter));
  assert(!isPageActive(m, DemoPage.textLabel));

  m.activePage = DemoPage.scrollbars;
  assert(isPageActive(m, DemoPage.scrollbars));

  assert(
    formatPageStatus(DemoPage.button, "Clicks: 3") ==
      "[Tab/1-9] Page 3: Hover Buttons | Clicks: 3 | [Q/Esc] Quit"
  );
  assert(
    formatPageStatus(DemoPage.layoutPainter, "") ==
      "[Tab/1-9] Page 1: Layout | [Q/Esc] Quit"
  );

  auto tabs = headerTabNames();
  assert(tabs.length == 9);
  assert(tabs[0] == "[1] Layout & Paint");
  assert(tabs[5] == "[6] Scrollbars");
  assert(tabs[6] == "[7] VirtList");
  assert(tabs[7] == "[8] Knob (Lock)");
  assert(tabs[8] == "[9] Button");
}
