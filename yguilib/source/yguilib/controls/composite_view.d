/**
 * composite_view.d - Free-function helpers for composite control views,
 * controllers, entry maps, and builders without templated base classes.
 */
module yguilib.controls.composite_view;

import yguilib.model : ModelTracker;
import yguilib.uisystem : UiRegistry, UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.widget_view : WidgetView, WidgetViewBase;

/// Registers `viewWidget` with `view` if it is not already registered.
void ensureViewWidgetRegistered(WidgetView view, Widget viewWidget) {
  assert(view !is null, "view must not be null");
  assert(viewWidget !is null, "viewWidget must not be null");
  if (!view.isWidgetRegistered(viewWidget)) {
    view.registerViewWidget(viewWidget);
  }
}

/// Looks up the entry associated with `viewWidget` in `entries`.
/// `viewWidget` is allowed to be null (returns null).
Entry findEntry(Entry)(Entry[Widget] entries, Widget viewWidget) {
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
) {
  if (auto e = findEntry(entries, viewWidget)) {
    return __traits(getMember, e, field);
  }
  return typeof(__traits(getMember, Entry.init, field)).init;
}

/// Wraps `model` in a `ModelTracker!M` and binds it to `viewWidget` via `view`.
void bindCompositeModel(V, M)(V view, Widget viewWidget, M model) {
  assert(view !is null, "view must not be null");
  assert(viewWidget !is null, "viewWidget must not be null");
  assert(model !is null, "model must not be null");
  auto tracker = ModelTracker!M(model);
  view.bindModel(viewWidget, tracker);
}

/// Removes `viewWidget` from `entries` and unregisters it from `view` via
/// a non-virtual base call to `WidgetViewBase.unregisterViewWidget`.
void unregisterCompositeWidget(Entry)(
  WidgetViewBase view,
  ref Entry[Widget] entries,
  Widget viewWidget
) {
  assert(view !is null, "view must not be null");
  entries.remove(viewWidget);
  view.WidgetViewBase.unregisterViewWidget(viewWidget);
}

/// Updates every tracked entry in `entries`, invoking `onModelChanged` when
/// its model version changes, and clears `viewDirty` flags.
bool updateCompositeEntries(Entry)(
  Entry[Widget] entries,
  scope bool delegate(Entry) onModelChanged
) {
  assert(onModelChanged !is null, "onModelChanged must not be null");
  bool anyUpdated = false;
  foreach (w, entry; entries) {
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

/// Finds the first `WidgetView` in `views` that has registered `viewWidget`
/// and casts it to `V`. `viewWidget` is allowed to be null (returns null).
V findOwningView(V)(WidgetView[] views, Widget viewWidget) {
  if (viewWidget is null) {
    return null;
  }
  foreach (v; views) {
    if (v !is null && v.isWidgetRegistered(viewWidget)) {
      if (auto typed = cast(V) v) {
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

/// Stores `model` into builder `tracker` and marks `hasModel` true.
void assignBuilderModel(M)(
  ref ModelTracker!M tracker,
  ref bool hasModel,
  M model
) {
  assert(model !is null, "model must not be null");
  tracker = ModelTracker!M(model);
  hasModel = true;
}

/// Copies `src` into builder `tracker` and marks `hasModel` true.
void assignBuilderTracker(M)(
  ref ModelTracker!M tracker,
  ref bool hasModel,
  ref ModelTracker!M src
) {
  tracker = ModelTracker!M.from(src);
  hasModel = true;
}

/// Ensures builder `tracker` has a model when `!hasModel` by calling
/// `makeDefault`. `makeDefault` is required only when `!hasModel`.
void ensureDefaultModelTracker(M)(
  ref ModelTracker!M tracker,
  ref bool hasModel,
  scope M delegate() makeDefault
) {
  if (!hasModel) {
    assert(makeDefault !is null, "makeDefault must not be null");
    tracker = ModelTracker!M(makeDefault());
    hasModel = true;
  }
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.model : VersionedModel;

  final class DummyModel : VersionedModel {
    int count = 0;
  }

  final class DummyEntry {
    ModelTracker!DummyModel tracker;
    Widget part;
    string label;
    bool viewDirty = false;

    this(ref ModelTracker!DummyModel tracker) {
      this.tracker = ModelTracker!DummyModel.from(tracker);
    }
  }

  final class DummyView : WidgetViewBase {
    DummyEntry[Widget] entries;
    int bindCalls = 0;

    void bindModel(Widget viewWidget, ref ModelTracker!DummyModel tracker) {
      ensureViewWidgetRegistered(this, viewWidget);
      auto entry = new DummyEntry(tracker);
      entries[viewWidget] = entry;
      bindCalls++;
    }

    override void unregisterViewWidget(Widget viewWidget) {
      unregisterCompositeWidget(this, entries, viewWidget);
    }

    override bool update() {
      return updateCompositeEntries(entries, (DummyEntry e) {
        return true;
      });
    }
  }

  auto ui = new UiSystemImpl(null);
  auto w1 = ui.makeWidget();
  auto w2 = ui.makeWidget();
  auto part1 = ui.makeWidget();
  auto view = new DummyView();
  auto otherView = new DummyView();
  auto model = new DummyModel();

  ensureViewWidgetRegistered(view, w1);
  assert(view.isWidgetRegistered(w1));
  ensureViewWidgetRegistered(view, w1);
  assert(view.isWidgetRegistered(w1));

  bindCompositeModel(view, w1, model);
  assert(view.bindCalls == 1);
  auto e1 = findEntry(view.entries, w1);
  assert(e1 !is null);
  e1.part = part1;
  e1.label = "hello";

  assert(findEntry(view.entries, null) is null);
  assert(findEntry(view.entries, w2) is null);
  assert(entryField!("part")(view.entries, w1) is part1);
  assert(entryField!("label")(view.entries, w1) == "hello");
  assert(entryField!("part")(view.entries, w2) is null);
  assert(entryField!("label")(view.entries, null) is null);

  WidgetView[] views = [otherView, view];
  assert(findOwningView!DummyView(views, w1) is view);
  assert(findOwningView!DummyView(views, w2) is null);
  assert(findOwningView!DummyView(views, null) is null);

  assert(view.update());
  assert(!view.update());

  auto editable = e1.tracker.edit();
  editable.count = 7;
  e1.tracker.commit(editable);
  assert(view.update());

  e1.viewDirty = true;
  assert(view.update());
  assert(!e1.viewDirty);
  assert(!view.update());

  // Verify non-virtual base unregister avoids infinite recursion
  view.unregisterViewWidget(w1);
  assert(!view.isWidgetRegistered(w1));
  assert(findEntry(view.entries, w1) is null);
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.model : VersionedModel;
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
  bool hasModel = false;

  ensureDefaultModelTracker(tracker, hasModel, () {
    auto m = new SampleModel();
    m.id = 99;
    return m;
  });
  assert(hasModel);
  assert(tracker.model.id == 99);

  // Calling again when hasModel is true must not invoke delegate
  ensureDefaultModelTracker(tracker, hasModel, null);
  assert(tracker.model.id == 99);

  auto m2 = new SampleModel();
  m2.id = 123;
  assignBuilderModel(tracker, hasModel, m2);
  assert(hasModel && tracker.model is m2);

  auto m3 = new SampleModel();
  m3.id = 456;
  auto srcTracker = ModelTracker!SampleModel(m3);
  assignBuilderTracker(tracker, hasModel, srcTracker);
  assert(hasModel && tracker.model is m3);
}
