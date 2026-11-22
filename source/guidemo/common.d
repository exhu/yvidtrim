/**
 * common.d - Shared UI helpers and components for guidemo.
 */
module guidemo.common;

import guidemo.demo_model_helpers : formatPageStatus, isPageActive;
import guidemo.model : DebugDrawMode, DemoModel, DemoPage;
import yguilib.events : AppEvent;
import yguilib.events.keyboard : Keycode, Scancode;
import yguilib.model : ModelTracker;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget, WidgetUpdateScope;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : Background, Border,
  DebugDrawComponent, TextLabel;

/// Returns true if `ev` matches `targetKey` (case-insensitive for ASCII
/// letters) or `targetScan`.
bool isKey(in AppEvent ev, Keycode targetKey, Scancode targetScan) {
  if (ev.keyData.scancode == targetScan) {
    return true;
  }
  if (ev.keyData.key == targetKey) {
    return true;
  }
  // Handle potential uppercase ASCII keycode
  if (targetKey >= 'a' && targetKey <= 'z') {
    if (ev.keyData.key == (targetKey - 32)) {
      return true;
    }
  }
  return false;
}

/// Factory function to create standard section cards across all demo pages.
Widget makeSectionCard(
  UiSystem ui,
  Widget parent,
  RectF rect,
  string title,
  string name
) {
  const string cardName = (name.length > 0) ? name : "sectionCard";
  auto card = WidgetBuilder.make(ui)
    .parent(parent)
    .name(cardName)
    .rect(rect)
    .roundBg(ColorF(0.13f, 0.15f, 0.18f, 1.0f))
    .bgRadius(8.0f)
    .border(ColorF(0.25f, 0.28f, 0.35f, 1.0f))
    .borderWidth(1.0f)
    .build();

  WidgetBuilder.make(ui)
    .parent(card)
    .name(cardName ~ "Title")
    .rect(RectF(12, 10, rect.width - 24, 20))
    .text(title)
    .textColor(ColorF(0.95f, 0.95f, 0.95f, 1.0f))
    .build();

  return card;
}

/// Updates DebugDrawComponent on `pageRoot` for per-page debug draw modes.
void syncPageDebugDraw(Widget pageRoot, DebugDrawMode mode, bool isActive) {
  assert(pageRoot !is null, "pageRoot must not be null");
  const bool wantDebugDraw = isActive && (
    mode == DebugDrawMode.activePageVisible ||
    mode == DebugDrawMode.activePageWithHidden
  );
  const bool wantHidden = (mode == DebugDrawMode.activePageWithHidden);

  auto existing = pageRoot.components.debugDraw;
  if (!wantDebugDraw) {
    if (existing !is null) {
      pageRoot.components.debugDraw = null;
      pageRoot.update(WidgetUpdateScope.visuals);
    }
    return;
  }

  if (existing is null || !existing.enabled || !existing.recursive ||
      existing.drawHidden != wantHidden) {
    auto comp = new DebugDrawComponent();
    comp.enabled = true;
    comp.recursive = true;
    comp.drawHidden = wantHidden;
    pageRoot.components.debugDraw = comp;
    pageRoot.update(WidgetUpdateScope.visuals);
  }
}

/// Synchronizes the shared `DemoModel.statusText` for an active page.
/// Returns true if `statusText` was updated.
bool syncPageStatus(
  ref ModelTracker!DemoModel demoTracker,
  DemoPage page,
  string statusDetails
) {
  const auto m = demoTracker.model;
  if (!isPageActive(m, page)) {
    return false;
  }
  const string statusText = formatPageStatus(page, statusDetails);
  if (m.statusText == statusText) {
    return false;
  }
  auto dm = demoTracker.edit();
  dm.statusText = statusText;
  demoTracker.commit(dm);
  return true;
}

/// Synchronizes a page's visibility and debug draw component with `DemoModel`
/// (view-only update).
void syncPageShellView(
  const DemoModel m,
  DemoPage page,
  Widget pageRoot
) {
  assert(m !is null, "m must not be null");
  assert(pageRoot !is null, "pageRoot must not be null");
  const bool isActive = isPageActive(m, page);
  pageRoot.setVisible(isActive);
  syncPageDebugDraw(pageRoot, m.debugDrawMode, isActive);
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
  auto demoModel = new DemoModel();
  auto tracker = ModelTracker!DemoModel(demoModel);
  auto pageRoot = new Widget(ui.nextWidgetId());

  const string expectedStatus = formatPageStatus(
    DemoPage.layoutPainter,
    "status"
  );

  // Initially active (layoutPainter): visible, no debugDraw, status published
  syncPageShellView(tracker.model, DemoPage.layoutPainter, pageRoot);
  assert(syncPageStatus(tracker, DemoPage.layoutPainter, "status"));
  assert(pageRoot.visible);
  assert(pageRoot.components.debugDraw is null);
  assert(tracker.model.statusText == expectedStatus);

  // Second call with same statusDetails does not re-dirty
  assert(!syncPageStatus(tracker, DemoPage.layoutPainter, "status"));

  // Enable activePageVisible debugDraw mode
  auto m = tracker.edit();
  m.debugDrawMode = DebugDrawMode.activePageVisible;
  tracker.commit(m);
  syncPageShellView(tracker.model, DemoPage.layoutPainter, pageRoot);
  assert(pageRoot.components.debugDraw !is null);
  assert(pageRoot.components.debugDraw.enabled);
  assert(!pageRoot.components.debugDraw.drawHidden);

  // Switch to activePageWithHidden
  m = tracker.edit();
  m.debugDrawMode = DebugDrawMode.activePageWithHidden;
  tracker.commit(m);
  syncPageShellView(tracker.model, DemoPage.layoutPainter, pageRoot);
  assert(pageRoot.components.debugDraw !is null);
  assert(pageRoot.components.debugDraw.drawHidden);

  // Switch activePage away from layoutPainter: hidden and debugDraw cleared
  m = tracker.edit();
  m.activePage = DemoPage.textLabel;
  tracker.commit(m);
  assert(!syncPageStatus(tracker, DemoPage.layoutPainter, "status"));
  syncPageShellView(tracker.model, DemoPage.layoutPainter, pageRoot);
  assert(!pageRoot.visible);
  assert(pageRoot.components.debugDraw is null);
}
