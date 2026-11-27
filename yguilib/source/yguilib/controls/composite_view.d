/**
 * composite_view.d - Free-function helpers for composite control views,
 * controllers, entry maps, and builders without templated base classes.
 */
module yguilib.controls.composite_view;

import yguilib.model : ModelTracker, VersionedModel;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.widget_view : WidgetView;

/// Registers `viewWidget` with `view` if it is not already registered.
void ensureViewWidgetRegistered(WidgetView view, Widget viewWidget) {
  assert(view !is null, "view must not be null");
  assert(viewWidget !is null, "viewWidget must not be null");
  if (!view.isWidgetRegistered(viewWidget)) {
    view.registerViewWidget(viewWidget);
  }
}

/// Looks up the entry associated with `viewWidget` in `entries`.
/// `viewWidget` is allowed to be null. Returns null if `viewWidget` is null
/// or not found in `entries`.
Entry findEntry(Entry)(
  Entry[Widget] entries,
  Widget viewWidget
) if (is(typeof(null) : Entry)) {
  if (viewWidget is null) {
    return null;
  }
  if (auto p = viewWidget in entries) {
    return *p;
  }
  return null;
}

/// Returns `field` from the entry associated with `viewWidget`, or the field
/// type's `.init` value if `viewWidget` is null or unregistered.
auto entryField(string field, Entry)(
  Entry[Widget] entries,
  Widget viewWidget
) if (
  is(typeof(null) : Entry) &&
  __traits(hasMember, Entry, field) &&
  is(typeof(__traits(getMember, Entry.init, field).offsetof))
) {
  if (auto e = findEntry(entries, viewWidget)) {
    return __traits(getMember, e, field);
  }
  return typeof(__traits(getMember, Entry.init, field)).init;
}

/// Wraps `model` in a `ModelTracker!M` and binds it to `viewWidget` via `view`.
void bindCompositeModel(V, M : VersionedModel)(
  V view,
  Widget viewWidget,
  M model
) if (is(typeof(
  (V v, Widget w, ref ModelTracker!M t) { v.bindModel(w, t); }
))) {
  assert(view !is null, "view must not be null");
  assert(viewWidget !is null, "viewWidget must not be null");
  assert(model !is null, "model must not be null");
  auto tracker = ModelTracker!M(model);
  view.bindModel(viewWidget, tracker);
}

/// Updates every tracked entry in `entries`, invoking `onModelChanged` when
/// its model version changes, and clears `viewDirty` flags.
/// `onModelChanged` must not add to or remove from `entries` during iteration
/// (for example, by releasing a widget).
bool updateCompositeEntries(Entry)(
  Entry[Widget] entries,
  scope bool delegate(Entry) onModelChanged
) if (is(Entry == class)) {
  assert(onModelChanged !is null, "onModelChanged must not be null");
  bool anyUpdated = false;
  foreach (entry; entries) {
    if (entry.tracker.update()) {
      if (onModelChanged(entry)) {
        anyUpdated = true;
      }
    }
    if (entry.viewDirty) {
      entry.viewDirty = false;
      anyUpdated = true;
    }
  }
  return anyUpdated;
}

/// Finds the first `V` in `views` that has registered `viewWidget`.
/// `viewWidget` is allowed to be null. Returns null if `viewWidget` is null
/// or no matching view owns it.
V findOwningView(V : WidgetView)(WidgetView[] views, Widget viewWidget) {
  if (viewWidget is null) {
    return null;
  }
  foreach (v; views) {
    if (auto typed = cast(V) v) {
      if (typed.isWidgetRegistered(viewWidget)) {
        return typed;
      }
    }
  }
  return null;
}

/// Returns `registry` when non-null, or falls back to `ui`.
/// `registry` is allowed to be null.
UiRegistry resolveBuilderRegistry(UiSystem ui, UiRegistry registry) {
  assert(ui !is null, "ui must not be null");
  return (registry !is null) ? registry : ui;
}

/// Stores `model` into builder `tracker`.
void assignBuilderModel(M : VersionedModel)(
  ref ModelTracker!M tracker,
  M model
) {
  assert(model !is null, "model must not be null");
  tracker = ModelTracker!M(model);
}

/// Copies `src` into builder `tracker`. `src` must be initialized
/// (`src.model !is null`). Resets `lastSeenVersion` so the next `update()`
/// reports a change.
void assignBuilderTracker(M : VersionedModel)(
  ref ModelTracker!M tracker,
  ref ModelTracker!M src
) {
  assert(src.model !is null, "src must be initialized");
  tracker = ModelTracker!M.from(src);
}

/// Ensures builder `tracker` has a model when uninitialized by calling
/// `makeDefault`. `makeDefault` is required only when `tracker.model is null`.
void ensureDefaultModelTracker(M : VersionedModel)(
  ref ModelTracker!M tracker,
  scope M delegate() makeDefault
) {
  if (tracker.model is null) {
    assert(makeDefault !is null, "makeDefault must not be null");
    tracker = ModelTracker!M(makeDefault());
  }
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.widget_view : WidgetViewBase;

  final class DummyModel : VersionedModel {
    int count = 0;
  }

  final class DummyEntry {
    ModelTracker!DummyModel tracker;
    Widget part;
    string label;
    int tag = 0;
    bool viewDirty = false;

    this(ref ModelTracker!DummyModel tracker) {
      this.tracker = ModelTracker!DummyModel.from(tracker);
    }

    int helperMethod() {
      return 1;
    }
  }

  final class DummyView : WidgetViewBase {
    DummyEntry[Widget] entries;
    int bindCalls = 0;
    bool onChangedResult = true;

    void bindModel(Widget viewWidget, ref ModelTracker!DummyModel tracker) {
      ensureViewWidgetRegistered(this, viewWidget);
      if (auto existing = findEntry(entries, viewWidget)) {
        existing.tracker = ModelTracker!DummyModel.from(tracker);
      } else {
        entries[viewWidget] = new DummyEntry(tracker);
      }
      bindCalls++;
    }

    override void unregisterViewWidget(Widget viewWidget) {
      entries.remove(viewWidget);
      super.unregisterViewWidget(viewWidget);
    }

    override bool update() {
      return updateCompositeEntries(entries, (DummyEntry e) {
        return onChangedResult;
      });
    }
  }

  final class UnrelatedView : WidgetViewBase {
    override bool update() {
      return false;
    }
  }

  struct ValueEntry {
    ModelTracker!DummyModel tracker;
    bool viewDirty = false;
  }

  auto ui = new UiSystemImpl(null);
  auto w1 = ui.makeWidget();
  auto w2 = ui.makeWidget();
  auto part1 = ui.makeWidget();
  auto view = new DummyView();
  auto otherView = new DummyView();
  auto unrelatedView = new UnrelatedView();
  auto model = new DummyModel();

  ValueEntry[Widget] valueEntries;
  static assert(!__traits(compiles,
    updateCompositeEntries(valueEntries, (ValueEntry e) => true)
  ));
  static assert(!__traits(compiles,
    entryField!"helperMethod"(view.entries, w1)
  ));
  static assert(!__traits(compiles,
    bindCompositeModel(unrelatedView, w1, model)
  ));

  ensureViewWidgetRegistered(view, w1);
  assert(view.isWidgetRegistered(w1));
  ensureViewWidgetRegistered(view, w1);
  assert(view.isWidgetRegistered(w1));
  ensureViewWidgetRegistered(unrelatedView, w1);

  bindCompositeModel(view, w1, model);
  assert(view.bindCalls == 1);
  auto e1 = findEntry(view.entries, w1);
  assert(e1 !is null);
  e1.part = part1;
  e1.label = "hello";
  e1.tag = 42;

  assert(findEntry(view.entries, null) is null);
  assert(findEntry(view.entries, w2) is null);
  assert(entryField!("part")(view.entries, w1) is part1);
  assert(entryField!("label")(view.entries, w1) == "hello");
  assert(entryField!("tag")(view.entries, w1) == 42);
  assert(entryField!("part")(view.entries, w2) is null);
  assert(entryField!("label")(view.entries, null) is null);
  assert(entryField!("tag")(view.entries, w2) == 0);
  assert(entryField!("tag")(view.entries, null) == 0);

  // Skips null slots and unrelated WidgetView subclasses even if registered
  WidgetView[] views = [null, unrelatedView, otherView, view];
  assert(findOwningView!DummyView(views, w1) is view);
  assert(findOwningView!DummyView(views, w2) is null);
  assert(findOwningView!DummyView(views, null) is null);

  assert(view.update());
  assert(!view.update());

  // Re-binding an already-bound widget reuses its entry and triggers update
  auto model2 = new DummyModel();
  bindCompositeModel(view, w1, model2);
  assert(view.bindCalls == 2);
  assert(findEntry(view.entries, w1) is e1);
  assert(e1.part is part1);
  assert(e1.tracker.model is model2);
  assert(view.update());
  assert(!view.update());

  auto editable = e1.tracker.edit();
  editable.count = 7;
  e1.tracker.commit(editable);
  assert(view.update());

  // onModelChanged returning false keeps update() false unless viewDirty
  view.onChangedResult = false;
  editable = e1.tracker.edit();
  editable.count = 8;
  e1.tracker.commit(editable);
  assert(!view.update());

  editable = e1.tracker.edit();
  editable.count = 9;
  e1.tracker.commit(editable);
  e1.viewDirty = true;
  assert(view.update());
  assert(!e1.viewDirty);
  assert(!view.update());

  // Unregistering null or unknown widget is a safe no-op
  view.unregisterViewWidget(null);
  view.unregisterViewWidget(w2);
  assert(view.isWidgetRegistered(w1));

  // Verify unregister removes entry and base registration
  view.unregisterViewWidget(w1);
  assert(!view.isWidgetRegistered(w1));
  assert(findEntry(view.entries, w1) is null);
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.object_registry : ObjectRegistry;
  import yguilib.widget.widget_view : WidgetViewController;

  final class DummyRegistry : UiRegistry {
    ObjectRegistry!WidgetViewController ctrls;
    ObjectRegistry!WidgetView views;

    this() {
      ctrls = new ObjectRegistry!WidgetViewController();
      views = new ObjectRegistry!WidgetView();
    }

    override @property ObjectRegistry!WidgetViewController
    widgetViewControllers() {
      return ctrls;
    }

    override @property ObjectRegistry!WidgetView widgetViews() {
      return views;
    }
  }

  final class SampleModel : VersionedModel {
    int id = 1;
  }

  auto ui = new UiSystemImpl(null);
  auto customReg = new DummyRegistry();
  assert(resolveBuilderRegistry(ui, null) is ui);
  assert(resolveBuilderRegistry(ui, customReg) is customReg);

  ModelTracker!SampleModel tracker;
  assert(tracker.model is null);

  ensureDefaultModelTracker(tracker, () {
    auto m = new SampleModel();
    m.id = 99;
    return m;
  });
  assert(tracker.model !is null && tracker.model.id == 99);

  // Calling again when already initialized must not invoke delegate
  ensureDefaultModelTracker(tracker, null);
  assert(tracker.model.id == 99);

  auto m2 = new SampleModel();
  m2.id = 123;
  assignBuilderModel(tracker, m2);
  assert(tracker.model is m2);

  auto m3 = new SampleModel();
  m3.id = 456;
  auto srcTracker = ModelTracker!SampleModel(m3);
  assert(srcTracker.update());
  assert(!srcTracker.update());
  assignBuilderTracker(tracker, srcTracker);
  assert(tracker.model is m3);
  assert(tracker.update());
  assert(!tracker.update());
}
