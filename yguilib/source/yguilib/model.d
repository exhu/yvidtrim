module yguilib.model;

alias ModelVersion = size_t;

/// helps with versioning changes. Put code which updates fields between calls
/// to edit() and commit().
abstract class VersionedModel {
  @property ModelVersion modelVersion() {
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
    model = m;
  }
  T model;
  ModelVersion lastSeenVersion;

  /// true if new version
  bool update() {
    bool changed = model.modelVersion != lastSeenVersion;
    if (changed)
      lastSeenVersion = model.modelVersion;

    return changed;
  }
}
