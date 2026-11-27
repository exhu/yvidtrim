module yguilib.serhelpers;

import std.conv : to;
import std.json : JSONOptions, JSONType, JSONValue, toJSON;
import std.math : isInfinity, isNaN;
import std.traits : BaseClassesTuple, FieldNameTuple, hasUDA, isArray,
  isAssociativeArray, isBoolean, isDelegate, isFloatingPoint,
  isFunctionPointer, isIntegral, isPointer, isSomeString, isUnsigned;

/// UDA to exclude specific fields (e.g. cyclic parent references)
/// from reflection-based JSON serialization.
enum SerIgnore;

/// Converts any D value into a `std.json.JSONValue`.
JSONValue toJsonValue(T)(auto ref const T value) {
  static if (is(T == JSONValue)) {
    return cast(JSONValue) value;
  } else static if (is(T == enum)) {
    return JSONValue(to!string(value));
  } else static if (isSomeString!T) {
    return JSONValue(to!string(value));
  } else static if (isBoolean!T) {
    return JSONValue(cast(bool) value);
  } else static if (isIntegral!T) {
    static if (isUnsigned!T) {
      return JSONValue(cast(ulong) value);
    } else {
      return JSONValue(cast(long) value);
    }
  } else static if (isFloatingPoint!T) {
    if (isNaN(value)) {
      return JSONValue("NaN");
    }
    if (isInfinity(value)) {
      return JSONValue(value > 0 ? "infinity" : "-infinity");
    }
    return JSONValue(cast(double) value);
  } else {
    return toJsonComposite(value);
  }
}

/// Serializes any struct or class instance into a JSON string.
string serializeToJson(T)(auto ref const T value, bool pretty) {
  const JSONValue jv = toJsonValue(value);
  if (pretty) {
    return toJSON(jv, true, JSONOptions.specialFloatLiterals);
  }
  return toJSON(jv, false, JSONOptions.specialFloatLiterals);
}

/// Returns the unqualified type name for an object or interface instance at
/// runtime, or of a value's static type. Template arguments are dropped
/// (e.g. `Box!int` becomes `Box`).
string shortTypeName(T)(auto ref const T item) {
  static if (is(T == class) || is(T == interface)) {
    if (item is null) {
      return "null";
    }
    auto obj = cast(const Object) item;
    string fullName = (obj !is null) ? typeid(obj).name : typeid(item).name;
  } else {
    string fullName = T.stringof;
  }
  import std.string : indexOf, lastIndexOf;

  const bangIdx = fullName.indexOf('!');
  if (bangIdx >= 0) {
    fullName = fullName[0 .. bangIdx];
  }
  const dotIdx = fullName.lastIndexOf('.');
  return dotIdx >= 0 ? fullName[dotIdx + 1 .. $] : fullName;
}

private:

/// Helper to convert composite, reference, or fallback values to JSONValue.
JSONValue toJsonComposite(T)(auto ref const T value) {
  static if (is(T == struct)) {
    return serializeStructOrClass(value);
  } else static if (is(T == class) || is(T == interface)) {
    if (value is null) {
      return JSONValue(null);
    }
    return serializeStructOrClass(value);
  } else static if (isArray!T) {
    auto arr = new JSONValue[value.length];
    foreach (i, ref elem; value) {
      arr[i] = toJsonValue(elem);
    }
    return JSONValue(arr);
  } else static if (isAssociativeArray!T) {
    JSONValue[string] aaMap;
    foreach (k, ref v; value) {
      aaMap[to!string(k)] = toJsonValue(v);
    }
    return JSONValue(aaMap);
  } else static if (isPointer!T) {
    if (value is null) {
      return JSONValue(null);
    }
    return toJsonValue(*value);
  } else static if (isDelegate!T || isFunctionPointer!T) {
    if (value is null) {
      return JSONValue(null);
    }
    return JSONValue("<delegate>");
  } else static if (is(T == typeof(null))) {
    return JSONValue(null);
  } else {
    return JSONValue(to!string(value));
  }
}

void serializeFieldsOf(U, V)(
  auto ref const V value,
  ref JSONValue[string] fields
) {
  enum fieldNames = FieldNameTuple!U;
  static foreach (i; 0 .. fieldNames.length) {
    static if (!hasUDA!(__traits(getMember, U, fieldNames[i]), SerIgnore)) {
      static if (is(U == V)) {
        fields[fieldNames[i]] = toJsonValue(value.tupleof[i]);
      } else {
        fields[fieldNames[i]] = toJsonValue(
          (cast(const U) value).tupleof[i]
        );
      }
    }
  }
}

/// Helper to serialize struct or class fields.
JSONValue serializeStructOrClass(T)(auto ref const T value) {
  static if (__traits(hasMember, T, "toJsonValue") &&
    !is(typeof(T.toJsonValue) == void)) {
    return value.toJsonValue();
  } else static if (__traits(hasMember, T, "isNull") &&
    __traits(hasMember, T, "get")) {
    if (value.isNull) {
      return JSONValue(null);
    }
    return toJsonValue(value.get);
  } else {
    JSONValue[string] root;
    root["type"] = JSONValue(shortTypeName(value));

    JSONValue[string] fields;
    static if (is(T == class)) {
      static foreach_reverse (Base; BaseClassesTuple!T) {
        static if (!is(Base == Object)) {
          serializeFieldsOf!Base(value, fields);
        }
      }
    }
    serializeFieldsOf!T(value, fields);

    static if (__traits(hasMember, T, "onSerializeFields")) {
      value.onSerializeFields(fields);
    }

    root["fields"] = JSONValue(fields);
    return JSONValue(root);
  }
}

unittest {
  struct TestPoint {
    float x;
    float y;
  }

  TestPoint pt = TestPoint(12.5f, -4.0f);
  JSONValue jv = toJsonValue(pt);
  assert(jv.type == JSONType.object);
  assert(jv["type"].str == "TestPoint");
  assert(jv["fields"]["x"].floating == 12.5);
  assert(jv["fields"]["y"].floating == -4.0);

  string json = serializeToJson(pt, true);
  assert(json.length > 0);
}

unittest {
  import std.typecons : Nullable, nullable;

  enum ColorKind {
    red,
    green,
    blue,
  }

  class Node {
    string name;
    ColorKind color;
    Nullable!float optVal;
    @SerIgnore Node parent;
    Node child;

    this(string name) {
      this.name = name;
    }
  }

  auto n1 = new Node("root");
  n1.color = ColorKind.green;
  n1.optVal = nullable(42.0f);

  auto n2 = new Node("child");
  n2.parent = n1;
  n1.child = n2;

  JSONValue jv = toJsonValue(n1);
  assert(jv["type"].str == "Node");
  assert(jv["fields"]["name"].str == "root");
  assert(jv["fields"]["color"].str == "green");
  assert(jv["fields"]["optVal"].floating == 42.0);
  assert("parent" !in jv["fields"]);
  assert(jv["fields"]["child"]["type"].str == "Node");
  assert(jv["fields"]["child"]["fields"]["name"].str == "child");
  assert(jv["fields"]["child"]["fields"]["child"].type == JSONType.null_);

  Node nullNode = null;
  assert(toJsonValue(nullNode).type == JSONType.null_);
}

unittest {
  struct FloatSpecial {
    float infVal;
    float negInfVal;
    float nanVal;
  }

  FloatSpecial fs = FloatSpecial(float.infinity, -float.infinity, float.nan);
  JSONValue jv = toJsonValue(fs);
  assert(jv["fields"]["infVal"].str == "infinity");
  assert(jv["fields"]["negInfVal"].str == "-infinity");
  assert(jv["fields"]["nanVal"].str == "NaN");
}

unittest {
  interface TestItemInterface {}
  class TestDerived : TestItemInterface {}

  TestItemInterface item = new TestDerived();
  assert(shortTypeName(item) == "TestDerived");

  TestItemInterface nullItem = null;
  assert(shortTypeName(nullItem) == "null");

  int val = 42;
  assert(shortTypeName(val) == "int");

  // ulong > long.max
  const ulong bigUlong = ulong.max;
  const JSONValue bigJv = toJsonValue(bigUlong);
  assert(bigJv.type == JSONType.uinteger);
  assert(bigJv.uinteger == ulong.max);

  // Arrays
  const int[] nums = [1, 2, 3];
  const JSONValue arrJv = toJsonValue(nums);
  assert(arrJv.type == JSONType.array);
  assert(arrJv.array.length == 3);
  assert(arrJv.array[2].integer == 3);

  // Associative arrays
  const int[string] scores = ["a": 10, "b": 20];
  const JSONValue aaJv = toJsonValue(scores);
  assert(aaJv.type == JSONType.object);
  assert(aaJv["a"].integer == 10);
  assert(aaJv["b"].integer == 20);

  // Pointers (non-null and null)
  int target = 99;
  int* ptr = &target;
  assert(toJsonValue(ptr).integer == 99);
  int* nullPtr = null;
  assert(toJsonValue(nullPtr).type == JSONType.null_);

  // Template shortTypeName
  struct Box(U) {
    U value;
  }
  auto box = Box!int(7);
  assert(shortTypeName(box) == "Box");
  auto nestedBox = Box!(Box!int)(box);
  assert(shortTypeName(nestedBox) == "Box");

  // Base-class fields
  class BaseItem {
    int baseId = 5;
  }
  class DerivedItem : BaseItem {
    string label = "hi";
  }
  auto derived = new DerivedItem();
  const JSONValue derivedJv = toJsonValue(derived);
  assert(derivedJv["type"].str == "DerivedItem");
  assert(derivedJv["fields"]["baseId"].integer == 5);
  assert(derivedJv["fields"]["label"].str == "hi");
}
