module yguilib.model;

alias ModelVersion = size_t;

/// helps with versioning changes. Put code which updates fields between calls
/// to edit() and commit().
abstract class VersionedModel {
  @property ModelVersion modelVersion() const {
    return version_;
  }

  /// mark dirty
  void edit() {
    assert(!editStarted, "contains previously undeclared changes");
    editStarted = true;
  }

  /// finish editing, increment version
  void commit() {
    assert(editStarted, "changes not previously declared");
    version_ += 1;
    editStarted = false;
  }

protected:
  ModelVersion version_ = 1;

private:
  bool editStarted;
}

unittest {
  static class MyModel : VersionedModel {}
  auto m = new MyModel;
  m.edit();
  m.commit();
  assert(m.version_ == 2);
}

struct ModelTracker(T : VersionedModel) {
  this(T m) {
    assert(m !is null);
    this.m = m;
  }
  this(ref ModelTracker!T other) {
    this.m = other.m;
  }
  private T m;

  @property const(T) model() {
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

  ModelVersion lastSeenVersion;

  /// true if new version
  bool update() {
    bool changed = model.modelVersion != lastSeenVersion;
    if (changed)
      lastSeenVersion = model.modelVersion;

    return changed;
  }
}

unittest {
  static class MyModel : VersionedModel {}
  auto m = new MyModel;
  auto t = ModelTracker!MyModel(m);
  assert(t.update());
  assert(!t.update());
  m.edit();
  m.commit();
  assert(t.update());
  assert(!t.update());
  assert(m.version_ == 2);
  assert(t.lastSeenVersion == 2);
}
