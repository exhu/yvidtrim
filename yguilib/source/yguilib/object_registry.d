module yguilib.object_registry;

final class ObjectRegistry(T : Object) {
  /// may be null
  T getByName(string name) {
    return objMap[name];
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
