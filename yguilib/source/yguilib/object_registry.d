module yguilib.object_registry;

final class ObjectRegistry(T : Object) {
  /// may be null
  T getByName(string name) {
    if (auto p = name in objMap)
      return *p;
    return null;
  }
  bool register(string name, T obj) {
    assert(name !in objMap);
    if (name in objMap)
      return false;

    objMap[name] = obj;
    return true;
  }

  bool unregister(string name, T obj) {
    if (name in objMap && objMap[name] is obj) {
      objMap.remove(name);
      return true;
    }
    return false;
  }
private:
  T[string] objMap;
}

unittest {
  static class Dummy : Object {
    int id;
    this(int id) {
      this.id = id;
    }
  }

  auto registry = new ObjectRegistry!Dummy();

  // Initially empty lookup returns null
  assert(registry.getByName("nonexistent") is null);

  auto obj1 = new Dummy(1);
  auto obj2 = new Dummy(2);

  // Register successfully
  assert(registry.register("first", obj1));
  assert(registry.getByName("first") is obj1);

  // Cannot register duplicate name
  import core.exception : AssertError;
  bool caughtAssert = false;
  try {
    registry.register("first", obj2);
  } catch (AssertError) {
    caughtAssert = true;
  }
  assert(caughtAssert);

  // Unregister with mismatched object fails
  assert(!registry.unregister("first", obj2));
  assert(registry.getByName("first") is obj1);

  // Unregister nonexistent key fails
  assert(!registry.unregister("other", obj1));

  // Unregister matching object succeeds
  assert(registry.unregister("first", obj1));
  assert(registry.getByName("first") is null);

  // Re-registering after unregister succeeds
  assert(registry.register("first", obj2));
  assert(registry.getByName("first") is obj2);
}
