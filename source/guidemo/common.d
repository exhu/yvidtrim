/**
 * common.d - Shared UI helpers and components for guidemo.
 */
module guidemo.common;

import guidemo.model : DebugDrawMode, DemoModel;
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
  string name = null
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
  const bool wantDebugDraw = isActive &&
    (mode == DebugDrawMode.activePageVisible ||
     mode == DebugDrawMode.activePageWithHidden);
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

/// Synchronizes a page's visibility, debug draw component, and status text
/// with the shared DemoModel. Returns true if statusText was updated.
bool syncPageShell(
  ref ModelTracker!DemoModel demoTracker,
  size_t pageIndex,
  Widget pageRoot,
  string statusText
) {
  assert(pageRoot !is null, "pageRoot must not be null");
  const auto m = demoTracker.model;
  const bool isActive = (m.activePage == pageIndex);
  pageRoot.setVisible(isActive);
  syncPageDebugDraw(pageRoot, m.debugDrawMode, isActive);
  if (isActive && m.statusText != statusText) {
    auto dm = demoTracker.edit();
    dm.statusText = statusText;
    demoTracker.commit(dm);
    return true;
  }
  return false;
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
  auto demoModel = new DemoModel();
  auto tracker = ModelTracker!DemoModel(demoModel);
  auto pageRoot = new Widget(ui.nextWidgetId());

  // Initially active (activePage == 0): visible, no debugDraw, status published
  assert(syncPageShell(tracker, 0, pageRoot, "Page 1 status"));
  assert(pageRoot.visible);
  assert(pageRoot.components.debugDraw is null);
  assert(tracker.model.statusText == "Page 1 status");

  // Second call with same statusText does not re-dirty
  assert(!syncPageShell(tracker, 0, pageRoot, "Page 1 status"));

  // Enable activePageVisible debugDraw mode
  auto m = tracker.edit();
  m.debugDrawMode = DebugDrawMode.activePageVisible;
  tracker.commit(m);
  syncPageShell(tracker, 0, pageRoot, "Page 1 status");
  assert(pageRoot.components.debugDraw !is null);
  assert(pageRoot.components.debugDraw.enabled);
  assert(!pageRoot.components.debugDraw.drawHidden);

  // Switch to activePageWithHidden
  m = tracker.edit();
  m.debugDrawMode = DebugDrawMode.activePageWithHidden;
  tracker.commit(m);
  syncPageShell(tracker, 0, pageRoot, "Page 1 status");
  assert(pageRoot.components.debugDraw !is null);
  assert(pageRoot.components.debugDraw.drawHidden);

  // Switch activePage away from 0: hidden and debugDraw cleared
  m = tracker.edit();
  m.activePage = 1;
  tracker.commit(m);
  assert(!syncPageShell(tracker, 0, pageRoot, "Page 1 status"));
  assert(!pageRoot.visible);
  assert(pageRoot.components.debugDraw is null);
}
