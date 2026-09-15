module yguilib.model;

alias ModelVersion = size_t;

abstract class VersionedModel {
  @property ModelVersion modelVersion() {
    return version_;
  }

  void mutate(T : VersionedModel)(void delegate(T m) func) {
    func(cast(T)this);
    version_ += 1;
  }

protected:
  ModelVersion version_ = 1;
}

unittest {
  static class MyModel : VersionedModel {}
  auto m = new MyModel;
  m.mutate((MyModel m) {
      import std.stdio;
      writeln("mutate test");
    });

}

struct TrackedModel {
  VersionedModel model;
  ModelVersion lastSeenVersion;

  bool isChanged() {
    bool changed = model.modelVersion != lastSeenVersion;
    if (changed)
      lastSeenVersion = model.modelVersion;

    return changed;
  }
}
