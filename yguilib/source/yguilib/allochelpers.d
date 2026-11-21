module yguilib.allochelpers;

import core.lifetime : move;
import std.traits : hasIndirections, isPointer;
import std.typecons : Nullable;

/// Inline stack-backed buffer of up to `stackCap` elements that transparently
/// spills to a heap slice when capacity is exceeded.
///
/// Never stores an internal pointer to `stackBuf`, so value moves and NRVO
/// remain safe. Calling `clear()` returns to stack mode while retaining the
/// heap allocation for future spills.
struct SmallBuffer(T, size_t stackCap) {
  static assert(stackCap > 0, "SmallBuffer stackCap must be > 0");

  /// Number of elements currently stored.
  @property size_t length() const nothrow @safe {
    return usingHeap ? heapBuf.length : stackCount;
  }

  /// True when no elements are stored.
  @property bool empty() const nothrow @safe {
    return length == 0;
  }

  /// True when active storage has spilled to the heap slice.
  @property bool isOnHeap() const nothrow @safe {
    return usingHeap;
  }

  /// Appends `item` to the end, spilling to the heap if stack storage is full.
  void push(T item) {
    if (usingHeap) {
      heapBuf ~= move(item);
    } else if (stackCount < stackCap) {
      stackBuf[stackCount++] = move(item);
    } else {
      spillToHeap();
      heapBuf ~= move(item);
    }
  }

  /// Returns true if an element matching `item` is present (identity `is` for
  /// classes, interfaces, and pointers; `==` for value types). `null` is
  /// allowed for nullable reference/pointer types.
  bool contains(in T item) const {
    foreach (ref elem; opSlice()) {
      if (sameItem!T(elem, item)) {
        return true;
      }
    }
    return false;
  }

  /// Appends `item` only if not already present. Returns true if inserted.
  bool addUnique(T item) {
    if (contains(item)) {
      return false;
    }
    push(move(item));
    return true;
  }

  /// Replaces contents with a copy of `src`, using stack storage when
  /// `src.length <= stackCap`.
  void assignSlice(T[] src) {
    clear();
    if (src.length <= stackCap) {
      if (src.length > 0) {
        stackBuf[0 .. src.length] = src[];
      }
      stackCount = src.length;
    } else {
      usingHeap = true;
      heapBuf.length = 0;
      heapBuf.assumeSafeAppend();
      heapBuf ~= src;
    }
  }

  /// Replaces contents with `count` copies of `value`.
  void fillWith(size_t count, T value) {
    clear();
    if (count <= stackCap) {
      if (count > 0) {
        stackBuf[0 .. count] = value;
      }
      stackCount = count;
    } else {
      usingHeap = true;
      heapBuf.length = count;
      heapBuf.assumeSafeAppend();
      heapBuf[0 .. count] = value;
    }
  }

  /// Removes the element at `index`, shifting subsequent elements left.
  void removeAt(size_t index) {
    assert(index < length, "SmallBuffer removeAt index out of bounds");
    if (usingHeap) {
      foreach (i; index .. heapBuf.length - 1) {
        heapBuf[i] = move(heapBuf[i + 1]);
      }
      clearSlot(heapBuf[$ - 1]);
      heapBuf.length -= 1;
      heapBuf.assumeSafeAppend();
    } else {
      foreach (i; index .. stackCount - 1) {
        stackBuf[i] = move(stackBuf[i + 1]);
      }
      clearSlot(stackBuf[stackCount - 1]);
      stackCount--;
    }
  }

  /// Removes the first element matching `item`. Returns true if removed.
  /// `null` is allowed for nullable reference/pointer types.
  bool removeFirst(in T item) {
    const slice = opSlice();
    foreach (i, ref elem; slice) {
      if (sameItem!T(elem, item)) {
        removeAt(i);
        return true;
      }
    }
    return false;
  }

  /// Clears all elements, returning to stack mode while keeping any heap
  /// capacity for future spills.
  void clear() {
    if (usingHeap) {
      clearRange(heapBuf);
      heapBuf.length = 0;
      heapBuf.assumeSafeAppend();
      usingHeap = false;
    } else {
      clearRange(stackBuf[0 .. stackCount]);
    }
    stackCount = 0;
  }

  /// Returns a slice over the active elements.
  inout(T)[] opSlice() inout return {
    return usingHeap ? heapBuf : stackBuf[0 .. stackCount];
  }

  /// Returns a reference to the element at `idx`.
  ref inout(T) opIndex(size_t idx) inout return {
    assert(idx < length, "SmallBuffer index out of bounds");
    return usingHeap ? heapBuf[idx] : stackBuf[idx];
  }

  /// Supports `$` indexing.
  size_t opDollar() const nothrow @safe {
    return length;
  }

private:
  T[stackCap] stackBuf;
  size_t stackCount = 0;
  T[] heapBuf;
  bool usingHeap = false;

  void spillToHeap() {
    heapBuf.length = 0;
    heapBuf.assumeSafeAppend();
    heapBuf.reserve(stackCap * 2);
    foreach (i; 0 .. stackCount) {
      heapBuf ~= move(stackBuf[i]);
      clearSlot(stackBuf[i]);
    }
    stackCount = 0;
    usingHeap = true;
  }
}

/// Power-of-two circular FIFO queue with lazy allocation, amortized O(1)
/// push/pop, and move semantics.
struct RingBuffer(T) {
  /// Number of elements currently queued.
  @property size_t length() const nothrow @safe {
    return count;
  }

  /// True when the ring buffer contains no elements.
  @property bool empty() const nothrow @safe {
    return count == 0;
  }

  /// Current allocated slot capacity (0 before first allocation, otherwise a
  /// power of two).
  @property size_t capacity() const nothrow @safe {
    return buffer.length;
  }

  /// Ensures capacity for at least `minCapacity` elements (rounded up to a
  /// power of two), preserving FIFO order.
  void reserve(size_t minCapacity) {
    if (minCapacity == 0) {
      return;
    }
    const size_t target = nextPowerOfTwo(minCapacity);
    if (target <= buffer.length) {
      return;
    }
    reallocate(target);
  }

  /// Appends `item` to the back of the queue, growing if full.
  void push(T item) {
    if (buffer.length == 0) {
      reallocate(defaultInitialCapacity);
    } else if (count == buffer.length) {
      reallocate(buffer.length * 2);
    }
    const size_t tailIdx = (head + count) & (buffer.length - 1);
    buffer[tailIdx] = move(item);
    count++;
  }

  /// Pops and returns the front element, or a null `Nullable!T` if empty.
  Nullable!T tryPop() {
    if (count == 0) {
      return Nullable!T.init;
    }
    T item = move(buffer[head]);
    clearSlot(buffer[head]);
    head = (head + 1) & (buffer.length - 1);
    count--;
    return Nullable!T(move(item));
  }

  /// Removes all elements while retaining allocated buffer capacity.
  void clear() {
    static if (hasIndirections!T) {
      if (count > 0) {
        const size_t mask = buffer.length - 1;
        foreach (i; 0 .. count) {
          buffer[(head + i) & mask] = T.init;
        }
      }
    }
    head = 0;
    count = 0;
  }

  /// Returns a reference to the `idx`-th element in FIFO order.
  ref inout(T) opIndex(size_t idx) inout {
    assert(idx < count, "RingBuffer index out of bounds");
    return buffer[(head + idx) & (buffer.length - 1)];
  }

  /// Supports `$` indexing.
  size_t opDollar() const nothrow @safe {
    return count;
  }

  /// Iterates over queued elements in FIFO order (mutable).
  int opApply(scope int delegate(ref T) dg) {
    if (count == 0) {
      return 0;
    }
    const size_t mask = buffer.length - 1;
    foreach (i; 0 .. count) {
      const int res = dg(buffer[(head + i) & mask]);
      if (res != 0) {
        return res;
      }
    }
    return 0;
  }

  /// Iterates over queued elements in FIFO order (const).
  int opApply(scope int delegate(const ref T) dg) const {
    if (count == 0) {
      return 0;
    }
    const size_t mask = buffer.length - 1;
    foreach (i; 0 .. count) {
      const int res = dg(buffer[(head + i) & mask]);
      if (res != 0) {
        return res;
      }
    }
    return 0;
  }

private:
  enum size_t defaultInitialCapacity = 16;
  T[] buffer;
  size_t head = 0;
  size_t count = 0;

  void reallocate(size_t newCap) {
    auto newBuf = new T[newCap];
    if (count > 0) {
      const size_t mask = buffer.length - 1;
      foreach (i; 0 .. count) {
        newBuf[i] = move(buffer[(head + i) & mask]);
      }
    }
    buffer = newBuf;
    head = 0;
  }
}

/// Capacity-preserving dynamic array wrapper using `assumeSafeAppend()` and
/// GC-safe slot clearing on shrink operations.
struct ReusableArray(T) {
  /// Number of elements currently stored.
  @property size_t length() const nothrow @safe {
    return buf.length;
  }

  /// True when the array has no elements.
  @property bool empty() const nothrow @safe {
    return buf.length == 0;
  }

  /// Pre-allocates backing capacity for at least `count` elements.
  void reserve(size_t count) {
    buf.reserve(count);
  }

  /// Appends `item` to the end.
  void push(T item) {
    buf ~= move(item);
  }

  /// Removes the last element (requires non-empty array).
  void popBack() {
    assert(buf.length > 0, "ReusableArray popBack on empty array");
    clearSlot(buf[$ - 1]);
    buf.length -= 1;
    buf.assumeSafeAppend();
  }

  /// Pops and returns the last element, or a null `Nullable!T` if empty.
  Nullable!T tryPop() {
    if (buf.length == 0) {
      return Nullable!T.init;
    }
    T item = move(buf[$ - 1]);
    clearSlot(buf[$ - 1]);
    buf.length -= 1;
    buf.assumeSafeAppend();
    return Nullable!T(move(item));
  }

  /// Returns a reference to the last element (requires non-empty array).
  ref inout(T) back() inout {
    assert(buf.length > 0, "ReusableArray back on empty array");
    return buf[$ - 1];
  }

  /// Clears all elements while preserving the allocated backing buffer.
  void clear() {
    clearRange(buf);
    buf.length = 0;
    buf.assumeSafeAppend();
  }

  /// Releases the underlying backing slice so the GC can reclaim it.
  void releaseMemory() nothrow @safe {
    buf = null;
  }

  /// Returns true if an element matching `item` is present (identity `is` for
  /// classes, interfaces, and pointers; `==` for value types). `null` is
  /// allowed for nullable reference/pointer types.
  bool contains(in T item) const {
    foreach (ref elem; buf) {
      if (sameItem!T(elem, item)) {
        return true;
      }
    }
    return false;
  }

  /// Appends `item` only if not already present. Returns true if inserted.
  bool addUnique(T item) {
    if (contains(item)) {
      return false;
    }
    push(move(item));
    return true;
  }

  /// Inserts `item` at `index`, shifting elements at `index .. $` right.
  void insertAt(size_t index, T item) {
    assert(index <= buf.length, "ReusableArray insertAt index out of bounds");
    buf ~= move(item);
    if (index == buf.length - 1) {
      return;
    }
    T inserted = move(buf[$ - 1]);
    for (size_t i = buf.length - 1; i > index; i--) {
      buf[i] = move(buf[i - 1]);
    }
    buf[index] = move(inserted);
  }

  /// Removes the element at `index`, shifting subsequent elements left.
  void removeAt(size_t index) {
    assert(index < buf.length, "ReusableArray removeAt index out of bounds");
    foreach (i; index .. buf.length - 1) {
      buf[i] = move(buf[i + 1]);
    }
    clearSlot(buf[$ - 1]);
    buf.length -= 1;
    buf.assumeSafeAppend();
  }

  /// Removes the first element matching `item`. Returns true if removed.
  /// `null` is allowed for nullable reference/pointer types.
  bool removeFirst(in T item) {
    foreach (i, const ref elem; buf) {
      if (sameItem!T(elem, item)) {
        removeAt(i);
        return true;
      }
    }
    return false;
  }

  /// Stable in-place compaction keeping elements for which `keep` returns true.
  void compact(scope bool delegate(const ref T) keep) {
    assert(keep !is null, "ReusableArray compact predicate must not be null");
    size_t writeIdx = 0;
    foreach (readIdx; 0 .. buf.length) {
      if (keep(buf[readIdx])) {
        if (writeIdx != readIdx) {
          buf[writeIdx] = move(buf[readIdx]);
        }
        writeIdx++;
      }
    }
    clearRange(buf[writeIdx .. $]);
    buf.length = writeIdx;
    buf.assumeSafeAppend();
  }

  /// Swaps backing buffers with `other` in O(1) without allocation.
  void swapWith(ref ReusableArray!T other) nothrow @safe {
    T[] tmp = buf;
    buf = other.buf;
    other.buf = tmp;
  }

  /// Returns a slice over the active elements.
  inout(T)[] opSlice() inout {
    return buf;
  }

  /// Returns a reference to the element at `idx`.
  ref inout(T) opIndex(size_t idx) inout {
    assert(idx < buf.length, "ReusableArray index out of bounds");
    return buf[idx];
  }

  /// Supports `$` indexing.
  size_t opDollar() const nothrow @safe {
    return buf.length;
  }

private:
  T[] buf;
}

private:

bool sameItem(T)(const ref T a, const ref T b) {
  static if (is(T == class) || is(T == interface) || isPointer!T) {
    return a is b;
  } else {
    return a == b;
  }
}

void clearSlot(T)(ref T slot) {
  static if (hasIndirections!T) {
    slot = T.init;
  }
}

void clearRange(T)(T[] slice) {
  static if (hasIndirections!T) {
    slice[] = T.init;
  }
}

size_t nextPowerOfTwo(size_t n) nothrow @safe pure {
  if (n <= 1) {
    return 1;
  }
  size_t cap = 1;
  while (cap < n) {
    assert(cap <= (size_t.max >> 1), "nextPowerOfTwo overflow");
    cap <<= 1;
  }
  return cap;
}

// ============================================================================
// Unit Tests
// ============================================================================

unittest {
  // SmallBuffer: stack-only, exact stackCap, spill, clear & heap reuse,
  // assignSlice, fillWith, removeAt, removeFirst, NRVO return.
  SmallBuffer!(int, 4) sb;
  assert(sb.empty);
  assert(sb.length == 0);
  assert(!sb.isOnHeap);

  sb.push(10);
  sb.push(20);
  sb.push(30);
  sb.push(40);
  assert(sb.length == 4);
  assert(!sb.empty);
  assert(!sb.isOnHeap);
  assert(sb[] == [10, 20, 30, 40]);
  assert(sb[0] == 10 && sb[$ - 1] == 40);

  // Spill to heap on 5th push.
  sb.push(50);
  assert(sb.isOnHeap);
  assert(sb.length == 5);
  assert(sb[] == [10, 20, 30, 40, 50]);
  const int* firstHeapPtr = sb[].ptr;
  assert(firstHeapPtr !is null);

  // clear() returns to stack mode while retaining heap capacity.
  sb.clear();
  assert(sb.empty);
  assert(!sb.isOnHeap);
  assert(sb.length == 0);

  // Refill and re-spill: should reuse existing heap allocation.
  foreach (i; 1 .. 6) {
    sb.push(i * 100);
  }
  assert(sb.isOnHeap);
  assert(sb[] == [100, 200, 300, 400, 500]);
  assert(sb[].ptr is firstHeapPtr);

  // removeAt / removeFirst on heap.
  sb.removeAt(1);
  assert(sb[] == [100, 300, 400, 500]);
  assert(sb.removeFirst(400));
  assert(!sb.removeFirst(999));
  assert(sb[] == [100, 300, 500]);

  // assignSlice: stack path and heap path.
  int[] shortSrc = [1, 2, 3];
  sb.assignSlice(shortSrc);
  assert(!sb.isOnHeap);
  assert(sb[] == [1, 2, 3]);

  // removeAt / removeFirst on stack.
  sb.removeAt(1);
  assert(sb[] == [1, 3]);
  assert(sb.removeFirst(1));
  assert(!sb.removeFirst(42));
  assert(sb[] == [3]);

  int[] longSrc = [1, 2, 3, 4, 5, 6];
  sb.assignSlice(longSrc);
  assert(sb.isOnHeap);
  assert(sb[] == [1, 2, 3, 4, 5, 6]);

  // fillWith: stack path and heap path.
  sb.fillWith(3, 7);
  assert(!sb.isOnHeap);
  assert(sb[] == [7, 7, 7]);

  sb.fillWith(6, 9);
  assert(sb.isOnHeap);
  assert(sb[] == [9, 9, 9, 9, 9, 9]);

  // Value return (NRVO / value move safety).
  static SmallBuffer!(int, 4) makeSmallBuf() {
    SmallBuffer!(int, 4) local;
    local.push(11);
    local.push(22);
    return local;
  }

  auto returned = makeSmallBuf();
  assert(!returned.isOnHeap);
  assert(returned[] == [11, 22]);
  returned[0] = 33;
  assert(returned[] == [33, 22]);
}

unittest {
  // SmallBuffer & ReusableArray: contains, addUnique, removeFirst with
  // interface, class (overridden opEquals proving `is`), pointer, value types.
  interface ItemIface {
    int id() const;
  }

  class EqualByValue : ItemIface {
    int val;

    this(int v) {
      val = v;
    }

    int id() const {
      return val;
    }

    override bool opEquals(Object other) const {
      auto rhs = cast(const EqualByValue) other;
      return rhs !is null && rhs.val == val;
    }
  }

  auto c1 = new EqualByValue(7);
  auto c2 = new EqualByValue(7);
  assert(c1 == c2);
  assert(c1 !is c2);

  // Class identity semantics in SmallBuffer and ReusableArray.
  SmallBuffer!(EqualByValue, 2) sbClass;
  assert(sbClass.addUnique(c1));
  assert(!sbClass.addUnique(c1));
  assert(sbClass.addUnique(c2));
  assert(sbClass.contains(c1));
  assert(sbClass.contains(c2));
  assert(sbClass.removeFirst(c1));
  assert(!sbClass.contains(c1));
  assert(sbClass.contains(c2));
  assert(sbClass.stackBuf[1] is null);

  ReusableArray!EqualByValue raClass;
  assert(raClass.addUnique(c1));
  assert(!raClass.addUnique(c1));
  assert(raClass.addUnique(c2));
  assert(raClass.length == 2);
  assert(raClass.removeFirst(c1));
  assert(raClass.length == 1 && raClass[0] is c2);

  // Interface identity semantics.
  ItemIface i1 = c1;
  ItemIface i2 = c2;
  SmallBuffer!(ItemIface, 2) sbIface;
  assert(sbIface.addUnique(i1));
  assert(sbIface.addUnique(i2));
  assert(!sbIface.addUnique(i1));
  assert(sbIface.removeFirst(i1));
  assert(sbIface.length == 1 && sbIface[0] is i2);

  ReusableArray!ItemIface raIface;
  assert(raIface.addUnique(i1));
  assert(raIface.addUnique(i2));
  assert(raIface.contains(i2));
  assert(raIface.removeFirst(i2));
  assert(raIface.length == 1 && raIface[0] is i1);

  // Pointer identity semantics.
  int a = 5;
  int b = 5;
  SmallBuffer!(int*, 2) sbPtr;
  assert(sbPtr.addUnique(&a));
  assert(sbPtr.addUnique(&b));
  assert(!sbPtr.addUnique(&a));
  assert(sbPtr.removeFirst(&a));
  assert(sbPtr.length == 1 && sbPtr[0] is &b);

  ReusableArray!(int*) raPtr;
  assert(raPtr.addUnique(&a));
  assert(raPtr.addUnique(&b));
  assert(raPtr.removeFirst(&b));
  assert(raPtr.length == 1 && raPtr[0] is &a);

  // Value types: ulong, string, struct.
  SmallBuffer!(ulong, 2) sbUlong;
  assert(sbUlong.addUnique(100UL));
  assert(!sbUlong.addUnique(100UL));
  assert(sbUlong.addUnique(200UL));
  assert(sbUlong.removeFirst(100UL));
  assert(sbUlong[] == [200UL]);

  ReusableArray!string raStr;
  assert(raStr.addUnique("alpha"));
  assert(!raStr.addUnique("alpha"));
  assert(raStr.addUnique("beta"));
  assert(raStr.contains("beta"));
  assert(raStr.removeFirst("alpha"));
  assert(raStr[] == ["beta"]);

  struct Pair {
    int x;
    int y;
  }

  SmallBuffer!(Pair, 2) sbPair;
  assert(sbPair.addUnique(Pair(1, 2)));
  assert(!sbPair.addUnique(Pair(1, 2)));
  assert(sbPair.addUnique(Pair(3, 4)));
  assert(sbPair.removeFirst(Pair(1, 2)));
  assert(sbPair[] == [Pair(3, 4)]);
}

unittest {
  // RingBuffer: lazy init, reserve rounding & order preservation,
  // wrap-around at constant capacity, FIFO across growth, opIndex, opApply
  // (mutable & const), clear() preserving capacity, GC slot clearing.
  RingBuffer!int rb;
  assert(rb.empty);
  assert(rb.length == 0);
  assert(rb.capacity == 0);
  assert(rb.tryPop().isNull);

  // Non-power-of-two reserve rounds up.
  rb.reserve(0);
  assert(rb.capacity == 0);
  rb.reserve(3);
  assert(rb.capacity == 4);

  // Fill and wrap around at constant capacity 4.
  rb.push(1);
  rb.push(2);
  rb.push(3);
  assert(rb.tryPop().get == 1);
  assert(rb.tryPop().get == 2);
  rb.push(4);
  rb.push(5);
  rb.push(6);
  assert(rb.capacity == 4);
  assert(rb.length == 4);
  assert(rb[0] == 3 && rb[1] == 4 && rb[2] == 5 && rb[$ - 1] == 6);

  // Reserve while wrapped preserves FIFO order.
  rb.reserve(5);
  assert(rb.capacity == 8);
  assert(rb.length == 4);
  assert(rb[0] == 3 && rb[1] == 4 && rb[2] == 5 && rb[3] == 6);

  // Grow via push while wrapped.
  assert(rb.tryPop().get == 3);
  assert(rb.tryPop().get == 4);
  foreach (v; 7 .. 14) {
    rb.push(v);
  }
  assert(rb.capacity == 16);
  assert(rb.length == 9);
  foreach (i; 0 .. 9) {
    assert(rb[i] == cast(int)(5 + i));
  }

  // Mutable opApply.
  foreach (ref v; rb) {
    v *= 10;
  }

  // Const opApply.
  static int sumConst(ref const RingBuffer!int r) {
    int total = 0;
    foreach (const ref v; r) {
      total += v;
    }
    return total;
  }
  assert(sumConst(rb) == 810);

  // Early break in opApply.
  int seen = 0;
  foreach (ref v; rb) {
    seen++;
    if (v == 70) {
      break;
    }
  }
  assert(seen == 3);

  // clear() preserves capacity.
  const size_t capBeforeClear = rb.capacity;
  rb.clear();
  assert(rb.empty);
  assert(rb.length == 0);
  assert(rb.capacity == capBeforeClear);
  assert(rb.tryPop().isNull);

  // Lazy init default capacity on first push.
  RingBuffer!int lazyRb;
  lazyRb.push(42);
  assert(lazyRb.capacity == 16);
  assert(lazyRb.tryPop().get == 42);
}

unittest {
  // RingBuffer: move semantics (non-copyable struct and postblit counter)
  // and GC reference clearing.
  static struct MoveOnly {
    int value;
    @disable this(this);
  }

  RingBuffer!MoveOnly moRb;
  moRb.reserve(2);
  moRb.push(MoveOnly(10));
  moRb.push(MoveOnly(20));
  // Trigger reallocation while populated.
  moRb.push(MoveOnly(30));
  auto moPopped = moRb.tryPop();
  assert(!moPopped.isNull && moPopped.get.value == 10);
  auto moSecond = moRb.tryPop();
  assert(!moSecond.isNull && moSecond.get.value == 20);
  moRb.clear();
  assert(moRb.empty);

  static int postblitCount = 0;

  struct MoveTracked {
    int value;

    this(this) {
      postblitCount++;
    }
  }

  postblitCount = 0;
  RingBuffer!MoveTracked rb;
  rb.reserve(2);
  rb.push(MoveTracked(10));
  rb.push(MoveTracked(20));
  rb.push(MoveTracked(30));
  // Push and reallocation must move without copying.
  assert(postblitCount == 0);
  auto popped = rb.tryPop();
  assert(!popped.isNull && popped.get.value == 10);

  // GC reference clearing on tryPop and clear.
  class RefObj {
    int id;

    this(int id) {
      this.id = id;
    }
  }

  RingBuffer!RefObj refRb;
  refRb.reserve(4);
  refRb.push(new RefObj(1));
  refRb.push(new RefObj(2));
  auto first = refRb.tryPop();
  assert(!first.isNull && first.get.id == 1);
  assert(refRb.buffer[0] is null);
  refRb.clear();
  assert(refRb.buffer[1] is null);
}

unittest {
  // ReusableArray: push, popBack, tryPop, back, clear ptr stability,
  // releaseMemory, insertAt, removeAt, removeFirst, compact, swapWith,
  // GC reference clearing.
  ReusableArray!int ra;
  assert(ra.empty);
  assert(ra.length == 0);
  assert(ra.tryPop().isNull);

  ra.reserve(8);
  ra.push(10);
  ra.push(20);
  ra.push(30);
  assert(ra.length == 3);
  assert(ra.back == 30);
  assert(ra[0] == 10 && ra[$ - 1] == 30);

  const int* stablePtr = ra[].ptr;
  assert(stablePtr !is null);

  ra.popBack();
  assert(ra[] == [10, 20]);
  auto popped = ra.tryPop();
  assert(!popped.isNull && popped.get == 20);
  assert(ra[] == [10]);

  ra.clear();
  assert(ra.empty);
  ra.push(99);
  assert(ra[].ptr is stablePtr);
  assert(ra[] == [99]);

  // insertAt: front, middle, end.
  ra.insertAt(0, 1);
  ra.insertAt(1, 50);
  ra.insertAt(ra.length, 200);
  assert(ra[] == [1, 50, 99, 200]);

  // removeAt / removeFirst.
  ra.removeAt(1);
  assert(ra[] == [1, 99, 200]);
  assert(ra.removeFirst(99));
  assert(!ra.removeFirst(777));
  assert(ra[] == [1, 200]);

  // compact: mixed, all, none.
  ra.clear();
  foreach (v; [1, 2, 3, 4, 5, 6]) {
    ra.push(v);
  }
  ra.compact((const ref int v) => (v % 2) == 0);
  assert(ra[] == [2, 4, 6]);
  ra.compact((const ref int v) => v > 0);
  assert(ra[] == [2, 4, 6]);
  ra.compact((const ref int v) => false);
  assert(ra.empty);

  // swapWith.
  ReusableArray!int other;
  ra.push(1);
  ra.push(2);
  other.push(10);
  const int* raPtrBefore = ra[].ptr;
  const int* otherPtrBefore = other[].ptr;
  ra.swapWith(other);
  assert(ra[] == [10] && ra[].ptr is otherPtrBefore);
  assert(other[] == [1, 2] && other[].ptr is raPtrBefore);

  // releaseMemory.
  ra.releaseMemory();
  assert(ra.empty);
  assert(ra[].ptr is null);

  // GC reference clearing on popBack, tryPop, removeAt, compact, clear.
  class Holder {
    int n;

    this(int n) {
      this.n = n;
    }
  }

  ReusableArray!Holder rh;
  rh.reserve(8);
  foreach (i; 0 .. 5) {
    rh.push(new Holder(i));
  }
  Holder* raw = rh.buf.ptr;

  rh.popBack();
  assert(raw[4] is null);

  auto poppedRef = rh.tryPop();
  assert(!poppedRef.isNull && poppedRef.get.n == 3);
  assert(raw[3] is null);

  rh.removeAt(0);
  assert(raw[2] is null);

  rh.compact((const ref Holder h) => h.n == 2);
  assert(rh.length == 1 && rh[0].n == 2);
  assert(raw[1] is null);

  rh.clear();
  assert(raw[0] is null);
}
