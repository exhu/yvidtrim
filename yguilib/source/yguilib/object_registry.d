module yguilib.object_registry;

final class ObjectRegistry(T) if (is(T == class) || is(T == interface)) {
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
    if (name in objMap && cast(Object) objMap[name] is cast(Object) obj) {
      objMap.remove(name);
      return true;
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

  // Test with interface
  interface IDummy {
    int id();
  }
  static class Impl : IDummy {
    int _id;
    this(int id) {
      _id = id;
    }
    int id() {
      return _id;
    }
  }

  auto ifaceRegistry = new ObjectRegistry!IDummy();
  IDummy iface1 = new Impl(10);
  IDummy iface2 = new Impl(20);

  assert(ifaceRegistry.register("first", iface1));
  assert(ifaceRegistry.getByName("first") is iface1);
  assert(!ifaceRegistry.unregister("first", iface2));
  assert(ifaceRegistry.unregister("first", iface1));
  assert(ifaceRegistry.getByName("first") is null);

  // Test opApply iteration
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
}
