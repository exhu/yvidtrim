module yguilib.model;
abstract class Model {
  @property uint modelVersion() {
    return version_;
  }

  void mutate(void delegate(Model m) func) {
    func(this);
    version_ += 1;
  }

private:
  uint version_ = 1;
}

struct TrackedModel {
  Model model;
  uint lastSeenVersion;

  bool isChanged() {
    bool changed = model.modelVersion != lastSeenVersion;
    if (changed)
      lastSeenVersion = model.modelVersion;

    return changed;
  }
}
