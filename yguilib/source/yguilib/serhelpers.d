module yguilib.serhelpers;

import std.conv : to;
import std.json : JSONOptions, JSONType, JSONValue, toJSON;
import std.math : isFinite, isInfinity, isNaN;
import std.traits : FieldNameTuple, hasUDA, isArray, isAssociativeArray,
  isBasicType, isBoolean, isDelegate, isFloatingPoint, isFunctionPointer,
  isIntegral, isPointer, isSomeChar, isSomeString;

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
    return JSONValue(cast(long) value);
  } else static if (isFloatingPoint!T) {
    if (isNaN(value)) {
      return JSONValue("NaN");
    }
    if (isInfinity(value)) {
      return JSONValue(value > 0 ? "infinity" : "-infinity");
    }
    return JSONValue(cast(double) value);
  } else static if (is(T == struct)) {
    return serializeStructOrClass(value);
  } else static if (is(T == class) || is(T == interface)) {
    if (value is null) {
      return JSONValue(null);
    }
    return serializeStructOrClass(value);
  } else static if (isArray!T) {
    JSONValue[] arr;
    foreach (ref elem; value) {
      arr ~= toJsonValue(elem);
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

/// Serializes any struct or class instance into a pretty-formatted JSON string.
string serializeToJson(T)(auto ref const T value, bool pretty = true) {
  const JSONValue jv = toJsonValue(value);
  if (pretty) {
    return toJSON(jv, true, JSONOptions.specialFloatLiterals);
  }
  return toJSON(jv, false, JSONOptions.specialFloatLiterals);
}

private:

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
    root["type"] = JSONValue(T.stringof);

    JSONValue[string] fields;
    enum fieldNames = FieldNameTuple!T;
    static foreach (i; 0 .. fieldNames.length) {
      static if (!hasUDA!(__traits(getMember, T, fieldNames[i]), SerIgnore)) {
        fields[fieldNames[i]] = toJsonValue(value.tupleof[i]);
      }
    }

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

  string json = serializeToJson(pt);
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
