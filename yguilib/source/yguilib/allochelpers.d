/// Single-threaded allocation-minimizing container types (`SmallBuffer`,
/// `RingBuffer`, and `ReusableArray`).
///
/// None of these containers perform internal locking; external synchronization
/// (such as `MessageBus`) is required for any cross-thread access.
module yguilib.allochelpers;

import core.bitop : bsr;
import core.lifetime : move;
import std.traits : CopyTypeQualifiers, hasElaborateDestructor,
  hasIndirections, isFunctionPointer, isPointer, Unqual;
import std.typecons : Nullable;

/// Inline stack-backed buffer of up to `stackCap` elements that transparently
/// spills to a heap slice when capacity is exceeded.
///
/// Never stores an internal pointer to `stackBuf`, so value moves and NRVO
/// remain safe. Calling `clear()` returns to stack mode while retaining the
/// heap allocation for future spills. Does not support types with elaborate
/// destructors (`~this()`); use `RingBuffer` for RAII element types.
struct SmallBuffer(T, size_t stackCap) {
  static assert(stackCap > 0, "SmallBuffer stackCap must be > 0");
  static assert(
    !hasElaborateDestructor!T,
    "SmallBuffer does not support types with destructors; use RingBuffer"
  );

  @disable this(this);

  invariant {
    assert(usingHeap || count <= stackCap);
    assert(!usingHeap || count <= heapBuf.length);
  }

  /// Number of elements currently stored.
  @property size_t length() const nothrow @safe {
    return count;
  }

  /// True when no elements are stored.
  @property bool empty() const nothrow @safe {
    return count == 0;
  }

  /// Current element capacity of the active storage (stack or heap).
  @property size_t capacity() const nothrow @safe {
    return usingHeap ? heapBuf.length : stackCap;
  }

  /// True when active storage has spilled to the heap slice.
  @property bool isOnHeap() const nothrow @safe {
    return usingHeap;
  }

  /// Appends `item` to the end, spilling to the heap if stack storage is full.
  void push(T item) {
    if (!usingHeap && count == stackCap) {
      spillToHeap();
    } else if (usingHeap && count == heapBuf.length) {
      ensureHeapCapacity(count + 1);
    }
    if (usingHeap) {
      heapBuf[count++] = move(item);
    } else {
      stackBuf[count++] = move(item);
    }
  }

  /// Returns true if an element matching `item` is present (identity `is` for
  /// classes, interfaces, and pointers; `==` for value types, including
  /// struct `opEquals` and `NaN != NaN` for floats). `null` is allowed for
  /// nullable reference/pointer types.
  bool contains(in T item) const {
    return sliceContains!T(opSlice(), item);
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
  /// `src.length <= stackCap`. `src` must not overlap this buffer's storage.
  void assignSlice(AssignSliceSrc!T src) {
    assert(
      !slicesOverlap(src, stackBuf[]) && !slicesOverlap(src, heapBuf),
      "SmallBuffer assignSlice source must not overlap buffer storage"
    );
    clear();
    if (src.length <= stackCap) {
      if (src.length > 0) {
        stackBuf[0 .. src.length] = src[];
      }
      count = src.length;
    } else {
      ensureHeapCapacity(src.length);
      heapBuf[0 .. src.length] = src[];
      usingHeap = true;
      count = src.length;
    }
  }

  /// Replaces contents with `newCount` copies of `value`.
  void fillWith(size_t newCount, T value) {
    clear();
    if (newCount <= stackCap) {
      if (newCount > 0) {
        stackBuf[0 .. newCount] = value;
      }
      count = newCount;
    } else {
      ensureHeapCapacity(newCount);
      heapBuf[0 .. newCount] = value;
      usingHeap = true;
      count = newCount;
    }
  }

  /// Removes the element at `index`, shifting subsequent elements left.
  void removeAt(size_t index) {
    assert(index < count, "SmallBuffer removeAt index out of bounds");
    shiftLeftAndClearTail(opSlice(), index);
    count--;
  }

  /// Removes the first element matching `item`. Returns true if removed.
  /// Uses identity `is` for classes, interfaces, and pointers, and `==` for
  /// value types. `null` is allowed for nullable reference/pointer types.
  bool removeFirst(in T item) {
    const ptrdiff_t idx = findItemIndex!T(opSlice(), item);
    if (idx < 0) {
      return false;
    }
    removeAt(cast(size_t) idx);
    return true;
  }

  /// Clears all elements, returning to stack mode while keeping any heap
  /// capacity for future spills.
  void clear() {
    clearRange(opSlice());
    usingHeap = false;
    count = 0;
  }

  /// Returns a slice over the active elements.
  /// The returned slice is valid only until the next mutating call or move
  /// of this buffer.
  inout(T)[] opSlice() inout return {
    return usingHeap ? heapBuf[0 .. count] : stackBuf[0 .. count];
  }

  /// Returns a reference to the element at `idx`.
  /// The returned reference is valid only until the next mutating call or
  /// move of this buffer.
  ref inout(T) opIndex(size_t idx) inout return {
    assert(idx < count, "SmallBuffer index out of bounds");
    return usingHeap ? heapBuf[idx] : stackBuf[idx];
  }

  /// Supports `$` indexing.
  size_t opDollar() const nothrow @safe {
    return count;
  }

private:
  T[stackCap] stackBuf;
  T[] heapBuf;
  size_t count = 0;
  bool usingHeap = false;

  void ensureHeapCapacity(size_t minCap) {
    if (minCap <= heapBuf.length) {
      return;
    }
    assert(
      stackCap <= size_t.max / 2,
      "SmallBuffer heap capacity overflow"
    );
    const size_t newCap = growCapacity(
      heapBuf.length, minCap, stackCap * 2
    );
    const size_t activeCount = usingHeap ? count : 0;
    reallocateSlice(heapBuf, activeCount, newCap);
  }

  void spillToHeap() {
    ensureHeapCapacity(stackCap * 2);
    foreach (i; 0 .. count) {
      heapBuf[i] = move(stackBuf[i]);
      clearSlot(stackBuf[i]);
    }
    usingHeap = true;
  }
}

/// Power-of-two circular FIFO queue with lazy allocation, amortized O(1)
/// push/pop, and move semantics.
struct RingBuffer(T) {
  @disable this(this);

  invariant {
    assert(
      buffer.length == 0 || (buffer.length & (buffer.length - 1)) == 0
    );
    assert(count <= buffer.length);
    assert(buffer.length == 0 ? head == 0 : head < buffer.length);
  }

  /// Forward range over queued elements in FIFO order.
  static struct Range(Elem) {
    Elem[] buf;
    size_t head = 0;
    size_t remaining = 0;

    @property bool empty() const nothrow @safe @nogc pure {
      return remaining == 0;
    }

    @property ref Elem front() return nothrow @safe @nogc pure {
      assert(remaining > 0, "RingBuffer range front on empty range");
      return buf[head];
    }

    void popFront() nothrow @safe @nogc pure {
      assert(remaining > 0, "RingBuffer range popFront on empty range");
      head = (head + 1) & (buf.length - 1);
      remaining--;
    }
  }

  /// Number of elements currently queued.
  @property size_t length() const nothrow @safe {
    return count;
  }

  /// True when the ring buffer contains no elements.
  @property bool empty() const nothrow @safe {
    return count == 0;
  }

  /// Destroys all remaining queued elements.
  ~this() {
    clear();
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
    if (count == buffer.length) {
      const size_t newCap = growCapacity(
        buffer.length, count + 1, defaultInitialCapacity
      );
      reallocate(newCap);
    }
    const size_t tailIdx = (head + count) & (buffer.length - 1);
    buffer[tailIdx] = move(item);
    count++;
  }

  /// Pops and returns the front element, or a null `Nullable!T` if empty.
  Nullable!T tryPopFront() {
    if (count == 0) {
      return Nullable!T.init;
    }
    T item = move(buffer[head]);
    static if (hasIndirections!T && !hasElaborateDestructor!T) {
      clearSlot(buffer[head]);
    }
    head = (head + 1) & (buffer.length - 1);
    count--;
    return Nullable!T(move(item));
  }

  /// Removes all elements while retaining allocated buffer capacity.
  void clear() {
    static if (hasIndirections!T || hasElaborateDestructor!T) {
      if (count > 0) {
        const size_t mask = buffer.length - 1;
        foreach (i; 0 .. count) {
          clearSlot(buffer[(head + i) & mask]);
        }
      }
    }
    head = 0;
    count = 0;
  }

  /// Clears all elements and releases the backing buffer for GC reclamation.
  void releaseMemory() {
    clear();
    buffer = null;
  }

  /// Returns a reference to the `idx`-th element in FIFO order.
  /// The returned reference is valid only until the next mutating call or
  /// move of this buffer.
  ref inout(T) opIndex(size_t idx) inout return {
    assert(idx < count, "RingBuffer index out of bounds");
    return buffer[(head + idx) & (buffer.length - 1)];
  }

  /// Supports `$` indexing.
  size_t opDollar() const nothrow @safe {
    return count;
  }

  /// Returns a forward range over queued elements in FIFO order.
  /// The returned range is valid only until the next mutating call or move
  /// of this buffer.
  auto opSlice(this This)() nothrow @safe @nogc pure return {
    alias Elem = CopyTypeQualifiers!(This, T);
    return Range!Elem(buffer, head, count);
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
        const size_t srcIdx = (head + i) & mask;
        newBuf[i] = move(buffer[srcIdx]);
        static if (hasIndirections!T && !hasElaborateDestructor!T) {
          clearSlot(buffer[srcIdx]);
        }
      }
    }
    buffer = newBuf;
    head = 0;
  }
}

/// Capacity-preserving dynamic array wrapper with explicit capacity tracking
/// and GC-safe slot clearing on shrink operations.
///
/// Does not support types with elaborate destructors (`~this()`); use
/// `RingBuffer` for RAII element types.
struct ReusableArray(T) {
  static assert(
    !hasElaborateDestructor!T,
    "ReusableArray does not support types with destructors; use RingBuffer"
  );

  @disable this(this);

  invariant {
    assert(count <= buf.length);
  }

  /// Number of elements currently stored.
  @property size_t length() const nothrow @safe {
    return count;
  }

  /// True when the array has no elements.
  @property bool empty() const nothrow @safe {
    return count == 0;
  }

  /// Current allocated slot capacity.
  @property size_t capacity() const nothrow @safe {
    return buf.length;
  }

  /// Pre-allocates backing capacity for at least `minCap` elements.
  void reserve(size_t minCap) {
    if (minCap <= buf.length) {
      return;
    }
    reallocateSlice(buf, count, minCap);
  }

  /// Appends `item` to the end.
  void push(T item) {
    ensureCapacityForPush();
    buf[count++] = move(item);
  }

  /// Removes the last element (requires non-empty array).
  void popBack() {
    assert(count > 0, "ReusableArray popBack on empty array");
    count--;
    clearSlot(buf[count]);
  }

  /// Pops and returns the last element, or a null `Nullable!T` if empty.
  Nullable!T tryPopBack() {
    if (count == 0) {
      return Nullable!T.init;
    }
    count--;
    T item = move(buf[count]);
    clearSlot(buf[count]);
    return Nullable!T(move(item));
  }

  /// Returns a reference to the last element (requires non-empty array).
  /// The returned reference is valid only until the next mutating call or
  /// move of this array.
  ref inout(T) back() inout return {
    assert(count > 0, "ReusableArray back on empty array");
    return buf[count - 1];
  }

  /// Clears all elements while preserving the allocated backing buffer.
  void clear() {
    clearRange(buf[0 .. count]);
    count = 0;
  }

  /// Releases the underlying backing slice so the GC can reclaim it.
  void releaseMemory() nothrow @safe {
    buf = null;
    count = 0;
  }

  /// Returns true if an element matching `item` is present (identity `is` for
  /// classes, interfaces, and pointers; `==` for value types, including
  /// struct `opEquals` and `NaN != NaN` for floats). `null` is allowed for
  /// nullable reference/pointer types.
  bool contains(in T item) const {
    return sliceContains!T(opSlice(), item);
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
    assert(index <= count, "ReusableArray insertAt index out of bounds");
    ensureCapacityForPush();
    for (size_t i = count; i > index; i--) {
      buf[i] = move(buf[i - 1]);
    }
    buf[index] = move(item);
    count++;
  }

  /// Removes the element at `index`, shifting subsequent elements left.
  void removeAt(size_t index) {
    assert(index < count, "ReusableArray removeAt index out of bounds");
    shiftLeftAndClearTail(opSlice(), index);
    count--;
  }

  /// Removes the first element matching `item`. Returns true if removed.
  /// Uses identity `is` for classes, interfaces, and pointers, and `==` for
  /// value types. `null` is allowed for nullable reference/pointer types.
  bool removeFirst(in T item) {
    const ptrdiff_t idx = findItemIndex!T(opSlice(), item);
    if (idx < 0) {
      return false;
    }
    removeAt(cast(size_t) idx);
    return true;
  }

  /// Stable in-place compaction keeping elements for which `keep` returns true.
  /// The array state is unspecified if `keep` throws mid-iteration.
  void compact(Pred)(scope Pred keep)
    if (is(Unqual!(typeof(keep(buf[0]))) == bool)) {
    static if (
      is(Pred == delegate) || isPointer!Pred || is(Pred == class) ||
      isFunctionPointer!Pred || is(Pred == interface)
    ) {
      assert(
        keep !is null,
        "ReusableArray compact predicate must not be null"
      );
    }
    size_t writeIdx = 0;
    foreach (readIdx; 0 .. count) {
      if (keep(buf[readIdx])) {
        if (writeIdx != readIdx) {
          buf[writeIdx] = move(buf[readIdx]);
        }
        writeIdx++;
      }
    }
    clearRange(buf[writeIdx .. count]);
    count = writeIdx;
  }

  /// Swaps backing buffers with `other` in O(1) without allocation.
  void swapWith(ref ReusableArray!T other) nothrow @safe {
    T[] tmpBuf = buf;
    buf = other.buf;
    other.buf = tmpBuf;
    const size_t tmpCount = count;
    count = other.count;
    other.count = tmpCount;
  }

  /// Returns a slice over the active elements.
  /// The returned slice is valid only until the next mutating call or move
  /// of this array.
  inout(T)[] opSlice() inout return {
    return buf[0 .. count];
  }

  /// Returns a reference to the element at `idx`.
  /// The returned reference is valid only until the next mutating call or
  /// move of this array.
  ref inout(T) opIndex(size_t idx) inout return {
    assert(idx < count, "ReusableArray index out of bounds");
    return buf[idx];
  }

  /// Supports `$` indexing.
  size_t opDollar() const nothrow @safe {
    return count;
  }

private:
  enum size_t initialCapacity = 4;
  T[] buf;
  size_t count = 0;

  void ensureCapacityForPush() {
    if (count < buf.length) {
      return;
    }
    const size_t newCap = growCapacity(
      buf.length, count + 1, initialCapacity
    );
    reallocateSlice(buf, count, newCap);
  }
}

private:

template AssignSliceSrc(T) {
  static if (is(const(T) : T)) {
    alias AssignSliceSrc = const(T)[];
  } else {
    alias AssignSliceSrc = T[];
  }
}

bool sameItem(T)(const ref T a, const ref T b) {
  static if (is(T == class) || is(T == interface) || isPointer!T) {
    return a is b;
  } else {
    return a == b;
  }
}

ptrdiff_t findItemIndex(T)(const(T)[] slice, in T item) {
  foreach (i, const ref elem; slice) {
    if (sameItem!T(elem, item)) {
      return cast(ptrdiff_t) i;
    }
  }
  return -1;
}

bool sliceContains(T)(const(T)[] slice, in T item) {
  return findItemIndex!T(slice, item) >= 0;
}

void shiftLeftAndClearTail(T)(T[] slice, size_t index) {
  foreach (i; index .. slice.length - 1) {
    slice[i] = move(slice[i + 1]);
  }
  clearSlot(slice[$ - 1]);
}

void reallocateSlice(T)(ref T[] slice, size_t activeCount, size_t newCap) {
  auto newBuf = new T[newCap];
  foreach (i; 0 .. activeCount) {
    newBuf[i] = move(slice[i]);
  }
  if (activeCount > 0) {
    clearRange(slice[0 .. activeCount]);
  }
  slice = newBuf;
}

size_t growCapacity(
  size_t currentCap,
  size_t minCap,
  size_t initialCap
) nothrow @safe pure {
  size_t newCap = currentCap == 0 ? initialCap : currentCap;
  while (newCap < minCap) {
    assert(newCap <= size_t.max / 2, "Buffer capacity overflow");
    newCap *= 2;
  }
  return newCap;
}

bool slicesOverlap(T)(const(T)[] a, const(T)[] b) nothrow @trusted pure {
  if (a.length == 0 || b.length == 0) {
    return false;
  }
  const size_t aStart = cast(size_t) a.ptr;
  const size_t aEnd = cast(size_t) (a.ptr + a.length);
  const size_t bStart = cast(size_t) b.ptr;
  const size_t bEnd = cast(size_t) (b.ptr + b.length);
  return aStart < bEnd && bStart < aEnd;
}

void clearSlot(T)(ref T slot) {
  static if (hasIndirections!T || hasElaborateDestructor!T) {
    slot = T.init;
  }
}

void clearRange(T)(T[] slice) {
  static if (hasIndirections!T || hasElaborateDestructor!T) {
    slice[] = T.init;
  }
}

size_t nextPowerOfTwo(size_t n) nothrow @safe pure {
  if (n <= 1) {
    return 1;
  }
  enum size_t maxPow2 = size_t(1) << (size_t.sizeof * 8 - 1);
  assert(n <= maxPow2, "nextPowerOfTwo overflow");
  if (n > maxPow2) {
    assert(0, "nextPowerOfTwo overflow");
  }
  return size_t(1) << (bsr(n - 1) + 1);
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
  // wrap-around at constant capacity, FIFO across growth, opIndex, opSlice
  // range (mutable & const), clear() preserving capacity, GC slot clearing.
  RingBuffer!int rb;
  assert(rb.empty);
  assert(rb.length == 0);
  assert(rb.capacity == 0);
  assert(rb.tryPopFront().isNull);

  // Non-power-of-two reserve rounds up.
  rb.reserve(0);
  assert(rb.capacity == 0);
  rb.reserve(3);
  assert(rb.capacity == 4);

  // Fill and wrap around at constant capacity 4.
  rb.push(1);
  rb.push(2);
  rb.push(3);
  assert(rb.tryPopFront().get == 1);
  assert(rb.tryPopFront().get == 2);
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
  assert(rb.tryPopFront().get == 3);
  assert(rb.tryPopFront().get == 4);
  foreach (v; 7 .. 14) {
    rb.push(v);
  }
  assert(rb.capacity == 16);
  assert(rb.length == 9);
  foreach (i; 0 .. 9) {
    assert(rb[i] == cast(int)(5 + i));
  }

  // Mutable iteration via opSlice range.
  foreach (ref v; rb) {
    v *= 10;
  }

  // Const iteration via opSlice range.
  static int sumConst(ref const RingBuffer!int r) {
    int total = 0;
    foreach (const ref v; r) {
      total += v;
    }
    return total;
  }
  assert(sumConst(rb) == 810);

  // Early break in range iteration.
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
  assert(rb.tryPopFront().isNull);

  // Lazy init default capacity on first push.
  RingBuffer!int lazyRb;
  lazyRb.push(42);
  assert(lazyRb.capacity == 16);
  assert(lazyRb.tryPopFront().get == 42);
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
  auto moPopped = moRb.tryPopFront();
  assert(!moPopped.isNull && moPopped.get.value == 10);
  auto moSecond = moRb.tryPopFront();
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
  auto popped = rb.tryPopFront();
  assert(!popped.isNull && popped.get.value == 10);

  // GC reference clearing on tryPopFront and clear.
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
  auto first = refRb.tryPopFront();
  assert(!first.isNull && first.get.id == 1);
  assert(refRb.buffer[0] is null);
  refRb.clear();
  assert(refRb.buffer[1] is null);
}

unittest {
  // ReusableArray: push, popBack, tryPopBack, back, clear ptr stability,
  // releaseMemory, insertAt, removeAt, removeFirst, compact, swapWith,
  // GC reference clearing.
  ReusableArray!int ra;
  assert(ra.empty);
  assert(ra.length == 0);
  assert(ra.tryPopBack().isNull);

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
  auto popped = ra.tryPopBack();
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

  // GC reference clearing on popBack, tryPopBack, removeAt, compact, clear.
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

  auto poppedRef = rh.tryPopBack();
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

unittest {
  // H1: Copy prevention on all three containers.
  static assert(!__traits(compiles, {
    SmallBuffer!(int, 4) a;
    auto b = a;
  }));
  static assert(!__traits(compiles, {
    RingBuffer!int a;
    auto b = a;
  }));
  static assert(!__traits(compiles, {
    ReusableArray!int a;
    auto b = a;
  }));
}

unittest {
  // M3: Destructor rejection on SmallBuffer/ReusableArray and RAII in
  // RingBuffer.
  static struct WithDtor {
    int id = 0;
    static int dtorCount = 0;

    ~this() {
      if (id > 0) {
        dtorCount++;
      }
    }
  }

  static assert(!__traits(compiles, SmallBuffer!(WithDtor, 4)));
  static assert(!__traits(compiles, ReusableArray!WithDtor));

  // Copyable struct with destructor: reallocation, clear, and releaseMemory
  // move elements without double-destroying.
  WithDtor.dtorCount = 0;
  RingBuffer!WithDtor copyableRb;
  copyableRb.reserve(2);
  copyableRb.push(WithDtor(1));
  copyableRb.push(WithDtor(2));
  copyableRb.push(WithDtor(3));
  assert(WithDtor.dtorCount == 0);
  copyableRb.clear();
  assert(WithDtor.dtorCount == 3);
  copyableRb.push(WithDtor(4));
  copyableRb.push(WithDtor(5));
  assert(WithDtor.dtorCount == 3);
  copyableRb.releaseMemory();
  assert(WithDtor.dtorCount == 5);

  // Move-only RAII struct: Nullable in tryPopFront moves without copying.
  static struct RaiiHandle {
    int id = 0;
    static int dtorCount = 0;

    @disable this(this);

    ~this() {
      if (id > 0) {
        dtorCount++;
      }
    }
  }

  RaiiHandle.dtorCount = 0;
  RingBuffer!RaiiHandle rb;
  rb.reserve(2);
  rb.push(RaiiHandle(1));
  rb.push(RaiiHandle(2));
  rb.push(RaiiHandle(3));
  assert(RaiiHandle.dtorCount == 0);

  {
    auto popped = rb.tryPopFront();
    assert(!popped.isNull && popped.get.id == 1);
  }
  assert(RaiiHandle.dtorCount == 1);

  rb.clear();
  assert(RaiiHandle.dtorCount == 3);

  rb.push(RaiiHandle(4));
  rb.push(RaiiHandle(5));
  assert(RaiiHandle.dtorCount == 3);

  rb.releaseMemory();
  assert(RaiiHandle.dtorCount == 5);
  assert(rb.empty);
  assert(rb.capacity == 0);
}

unittest {
  // SmallBuffer GC reference clearing on spillToHeap, removeAt, and clear.
  class Item {
    int id;

    this(int id) {
      this.id = id;
    }
  }

  auto i1 = new Item(1);
  auto i2 = new Item(2);
  auto i3 = new Item(3);
  auto i4 = new Item(4);

  SmallBuffer!(Item, 2) sb;
  sb.push(i1);
  sb.push(i2);
  assert(sb.stackBuf[0] is i1);
  assert(sb.stackBuf[1] is i2);

  // Spill to heap must clear stackBuf slots.
  sb.push(i3);
  assert(sb.isOnHeap);
  assert(sb.stackBuf[0] is null);
  assert(sb.stackBuf[1] is null);
  assert(sb.heapBuf[0] is i1);
  assert(sb.heapBuf[1] is i2);
  assert(sb.heapBuf[2] is i3);

  sb.push(i4);
  assert(sb.length == 4);

  // removeAt in heap mode must clear vacated tail slot.
  sb.removeAt(1);
  assert(sb.length == 3);
  assert(sb[0] is i1 && sb[1] is i3 && sb[2] is i4);
  assert(sb.heapBuf[3] is null);

  // clear in heap mode must clear active heap slots.
  sb.clear();
  assert(!sb.isOnHeap);
  assert(sb.empty);
  assert(sb.heapBuf[0] is null);
  assert(sb.heapBuf[1] is null);
  assert(sb.heapBuf[2] is null);
}

unittest {
  // SmallBuffer edge cases: stackCap == 1, fillWith(0, ...), assignSlice([]),
  // and heap-mode removeAt down to empty followed by push.
  SmallBuffer!(int, 1) sb1;
  assert(sb1.capacity == 1);
  sb1.push(10);
  assert(!sb1.isOnHeap);
  assert(sb1[] == [10]);

  sb1.push(20);
  assert(sb1.isOnHeap);
  assert(sb1.capacity == 2);
  assert(sb1[] == [10, 20]);

  sb1.clear();
  assert(!sb1.isOnHeap);
  assert(sb1.empty);
  assert(sb1.capacity == 1);

  sb1.push(30);
  assert(!sb1.isOnHeap);
  assert(sb1[] == [30]);
  sb1.push(40);
  assert(sb1.isOnHeap);
  assert(sb1[] == [30, 40]);

  sb1.fillWith(0, 42);
  assert(!sb1.isOnHeap);
  assert(sb1.empty);

  sb1.push(1);
  sb1.push(2);
  assert(sb1.isOnHeap);
  sb1.assignSlice([]);
  assert(!sb1.isOnHeap);
  assert(sb1.empty);

  // Heap-mode removeAt down to empty stays in heap mode for subsequent push.
  sb1.push(100);
  sb1.push(200);
  assert(sb1.isOnHeap);
  sb1.removeAt(0);
  assert(sb1.isOnHeap);
  assert(sb1[] == [200]);
  sb1.removeAt(0);
  assert(sb1.empty);
  assert(sb1.length == 0);
  assert(sb1.isOnHeap);
  sb1.push(300);
  assert(sb1.isOnHeap);
  assert(sb1[] == [300]);
  sb1.clear();
  assert(!sb1.isOnHeap);
}

unittest {
  // M2: Self-aliasing assignSlice asserts in both stack and heap modes.
  import core.exception : AssertError;
  import std.exception : assertThrown;

  SmallBuffer!(int, 2) sb;
  sb.push(1);
  sb.push(2);
  assert(!sb.isOnHeap);
  assertThrown!AssertError(sb.assignSlice(sb[]));

  sb.push(3);
  assert(sb.isOnHeap);
  assertThrown!AssertError(sb.assignSlice(sb[]));
}

unittest {
  // ReusableArray: reference insertAt across growth, swapWith + clear, @nogc.
  class RefItem {
    int id;

    this(int id) {
      this.id = id;
    }
  }

  auto r0 = new RefItem(0);
  auto r1 = new RefItem(1);
  auto r2 = new RefItem(2);
  auto r3 = new RefItem(3);
  auto r4 = new RefItem(4);

  ReusableArray!RefItem ra;
  ra.insertAt(0, r0);
  ra.insertAt(0, r1);
  ra.insertAt(1, r2);
  ra.insertAt(ra.length, r3);
  assert(ra.capacity == 4);
  // Insert across growth from capacity 4 to 8.
  ra.insertAt(2, r4);
  assert(ra.capacity == 8);
  assert(ra.length == 5);
  assert(ra[0] is r1);
  assert(ra[1] is r2);
  assert(ra[2] is r4);
  assert(ra[3] is r0);
  assert(ra[4] is r3);

  ra.removeAt(1);
  assert(ra.length == 4);
  assert(ra.buf[4] is null);

  ra.clear();
  assert(ra.empty);
  foreach (i; 0 .. 4) {
    assert(ra.buf[i] is null);
  }

  // swapWith followed by clear() on both sides.
  ReusableArray!int a;
  ReusableArray!int b;
  a.reserve(8);
  b.reserve(16);
  a.push(1);
  a.push(2);
  b.push(10);
  const size_t capA = a.capacity;
  const size_t capB = b.capacity;
  a.swapWith(b);
  assert(a.capacity == capB && a[] == [10]);
  assert(b.capacity == capA && b[] == [1, 2]);
  a.clear();
  b.clear();
  assert(a.empty && a.capacity == capB);
  assert(b.empty && b.capacity == capA);

  // compact inside a @safe nothrow @nogc helper.
  static void keepEven(ref ReusableArray!int arr) @safe nothrow @nogc {
    arr.compact((const ref int v) => (v & 1) == 0);
  }

  foreach (v; 1 .. 7) {
    a.push(v);
  }
  keepEven(a);
  assert(a[] == [2, 4, 6]);
}

unittest {
  // RingBuffer: wrap-around opIndex writes, releaseMemory GC clearing,
  // and @safe nothrow @nogc pure foreach iteration.
  RingBuffer!int rb;
  rb.reserve(4);
  rb.push(1);
  rb.push(2);
  rb.push(3);
  assert(rb.tryPopFront().get == 1);
  assert(rb.tryPopFront().get == 2);
  rb.push(4);
  rb.push(5);
  rb.push(6);
  assert(rb.capacity == 4);
  assert(rb.length == 4);

  // Mutate wrapped elements via opIndex.
  rb[0] = 30;
  rb[1] = 40;
  rb[2] = 50;
  rb[3] = 60;
  assert(rb[0] == 30 && rb[1] == 40 && rb[2] == 50 && rb[3] == 60);

  int[4] collected;
  size_t idx = 0;
  foreach (const ref v; rb) {
    collected[idx++] = v;
  }
  assert(collected == [30, 40, 50, 60]);

  static void incrementAll(ref RingBuffer!int buf) @safe nothrow @nogc pure {
    foreach (ref v; buf) {
      v += 1;
    }
  }

  static int sumAll(ref const RingBuffer!int buf) @safe nothrow @nogc pure {
    int total = 0;
    foreach (const ref v; buf) {
      total += v;
    }
    return total;
  }

  incrementAll(rb);
  assert(sumAll(rb) == 184);

  rb.releaseMemory();
  assert(rb.empty);
  assert(rb.length == 0);
  assert(rb.capacity == 0);

  class RefNode {
    int val;

    this(int val) {
      this.val = val;
    }
  }

  RingBuffer!RefNode refRb;
  refRb.reserve(4);
  refRb.push(new RefNode(1));
  refRb.push(new RefNode(2));
  RefNode[] rawBuf = refRb.buffer;
  refRb.releaseMemory();
  assert(refRb.length == 0);
  assert(refRb.capacity == 0);
  assert(refRb.buffer is null);
  assert(rawBuf[0] is null);
  assert(rawBuf[1] is null);
}

unittest {
  // L1: nextPowerOfTwo edge cases including highest representable power of two.
  enum size_t maxPow2 = size_t(1) << (size_t.sizeof * 8 - 1);
  assert(nextPowerOfTwo(0) == 1);
  assert(nextPowerOfTwo(1) == 1);
  assert(nextPowerOfTwo(2) == 2);
  assert(nextPowerOfTwo(3) == 4);
  assert(nextPowerOfTwo(4) == 4);
  assert(nextPowerOfTwo(5) == 8);
  assert(nextPowerOfTwo(15) == 16);
  assert(nextPowerOfTwo(16) == 16);
  assert(nextPowerOfTwo(17) == 32);
  assert(nextPowerOfTwo(maxPow2) == maxPow2);
}
