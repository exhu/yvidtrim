module yguilib.model;

alias ModelVersion = size_t;

/// helps with versioning changes. Put code which updates fields between calls
/// to edit() and commit().
abstract class VersionedModel {
  @property ModelVersion modelVersion() const {
    return fModelVersion;
  }

  /// mark dirty
  void edit() {
    assert(!editStarted, "contains previously undeclared changes");
    editStarted = true;
  }

  /// finish editing, increment version
  void commit() {
    assert(editStarted, "changes not previously declared");
    fModelVersion += 1;
    editStarted = false;
  }

private:
  ModelVersion fModelVersion = 1;
  bool editStarted;
}

unittest {
  static class MyModel : VersionedModel {}
  auto m = new MyModel;
  m.edit();
  m.commit();
  assert(m.fModelVersion == 2);
}

struct ModelTracker(T : VersionedModel) {
  @disable this();

  this(T m) {
    assert(m !is null);
    this.m = m;
  }

  invariant {
    assert(m !is null);
  }

  static ModelTracker!T from(ref ModelTracker!T other) {
    return ModelTracker!T(other.m);
  }

  @property const(T) model() const {
    return m;
  }

  T edit() {
    m.edit();
    return m;
  }

  void commit(ref T pm) {
    assert(pm is m);
    m.commit();
    pm = null;
  }

  /// true if new version
  bool update() {
    bool changed = model.modelVersion != lastSeenVersion;
    if (changed)
      lastSeenVersion = model.modelVersion;

    return changed;
  }

private:
  T m;
  ModelVersion lastSeenVersion;
}

unittest {
  static class MyModel : VersionedModel {
    int value;
  }
  auto m = new MyModel;
  auto t = ModelTracker!MyModel(m);
  assert(t.update());
  assert(!t.update());
  m.edit();
  m.commit();
  assert(t.update());
  assert(!t.update());
  assert(m.fModelVersion == 2);
  assert(t.lastSeenVersion == 2);

  // Test from, edit, and commit on tracker
  auto t2 = ModelTracker!MyModel.from(t);
  assert(t2.model is m);
  assert(t2.update());
  assert(!t2.update());
  auto editable = t2.edit();
  editable.value = 42;
  t2.commit(editable);
  assert(editable is null);
  assert(t2.model.value == 42);
  assert(m.fModelVersion == 3);
  assert(t2.update());
  assert(t.update());
}
