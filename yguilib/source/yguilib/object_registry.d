module yguilib.object_registry;

final class ObjectRegistry(T) if (is(T == class) || is(T == interface)) {
  /// may be null
  T findByName(string name) {
    if (auto p = name in objMap)
      return *p;
    return null;
  }
  bool register(string name, T obj) {
    assert(obj !is null, "obj must not be null");
    if (name in objMap) {
      assert(false, "duplicate object registration");
      return false;
    }

    objMap[name] = obj;
    return true;
  }

  bool unregister(string name, T obj) {
    if (auto p = name in objMap) {
      if (cast(Object) *p is cast(Object) obj) {
        objMap.remove(name);
        return true;
      }
    }
    return false;
  }

  int opApply(scope int delegate(T) dg) {
    foreach (obj; objMap.byValue) {
      if (int res = dg(obj)) {
        return res;
      }
    }
    return 0;
  }

  int opApply(scope int delegate(string, T) dg) {
    foreach (name, obj; objMap) {
      if (int res = dg(name, obj)) {
        return res;
      }
    }
    return 0;
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
  assert(registry.findByName("nonexistent") is null);

  auto obj1 = new Dummy(1);
  auto obj2 = new Dummy(2);

  // Register successfully
  assert(registry.register("first", obj1));
  assert(registry.findByName("first") is obj1);

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
  assert(registry.findByName("first") is obj1);

  // Unregister nonexistent key fails
  assert(!registry.unregister("other", obj1));

  // Unregister matching object succeeds
  assert(registry.unregister("first", obj1));
  assert(registry.findByName("first") is null);

  // Re-registering after unregister succeeds
  assert(registry.register("first", obj2));
  assert(registry.findByName("first") is obj2);

  // Test with interface
  interface DummyInterface {
    int id();
  }
  static class Impl : DummyInterface {
    int fId;
    this(int id) {
      fId = id;
    }
    int id() {
      return fId;
    }
  }

  auto ifaceRegistry = new ObjectRegistry!DummyInterface();
  DummyInterface iface1 = new Impl(10);
  DummyInterface iface2 = new Impl(20);

  assert(ifaceRegistry.register("first", iface1));
  assert(ifaceRegistry.findByName("first") is iface1);
  assert(!ifaceRegistry.unregister("first", iface2));
  assert(ifaceRegistry.unregister("first", iface1));
  assert(ifaceRegistry.findByName("first") is null);

  // Test opApply iteration (1-arg, 2-arg, and early break)
  auto iterRegistry = new ObjectRegistry!Dummy();
  iterRegistry.register("a", new Dummy(100));
  iterRegistry.register("b", new Dummy(200));
  int sum = 0;
  int count = 0;
  foreach (item; iterRegistry) {
    sum += item.id;
    count++;
  }
  assert(count == 2);
  assert(sum == 300);

  int breakCount = 0;
  foreach (item; iterRegistry) {
    breakCount++;
    break;
  }
  assert(breakCount == 1);

  int twoArgSum = 0;
  size_t nameLenSum = 0;
  foreach (name, item; iterRegistry) {
    nameLenSum += name.length;
    twoArgSum += item.id;
  }
  assert(nameLenSum == 2);
  assert(twoArgSum == 300);

  int twoArgBreakCount = 0;
  foreach (name, item; iterRegistry) {
    twoArgBreakCount++;
    break;
  }
  assert(twoArgBreakCount == 1);
}
