module yguilib.model;

alias ModelVersion = size_t;

abstract class VersionedModel {
  @property ModelVersion modelVersion() {
    return version_;
  }

  void edit() {
    assert(!editStarted);
    editStarted = true;
  }

  void commit() {
    version_ += 1;
    editStarted = false;
  }

  deprecated
  void mutate(T : typeof(this))(void delegate(T m) func) {
    func(cast(T)this);
    version_ += 1;
  }

protected:
  ModelVersion version_ = 1;

private:
  bool editStarted;
}

unittest {
  static class MyModel : VersionedModel {}
  auto m = new MyModel;
  m.mutate((MyModel m) {
      import std.stdio;
      writeln("mutate test");
    });

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
