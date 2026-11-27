module yguilib.events.internal.message_bus;

package(yguilib):

import core.lifetime : move;
import core.thread : Thread, ThreadID;
import core.time : MonoTime, ticksToNSecs;
import std.typecons : Nullable;
import yguilib.allochelpers : RingBuffer;
import yguilib.clibs.sdl3;
import yguilib.events : AppEvent;

/**
 * Snapshot of event queue activity recorded by $(D MessageBus).
 */
struct EventQueueStats {
  ulong postedCount;
  ulong suppressedCount;
  ulong maxEventsPerSecond;
  double avgEventsPerSecond;
  double elapsedSeconds;
}

/**
 * Thread-safe ring-buffer FIFO event queue for UI event dispatch.
 *
 * Allows D-registered background threads to post $(D AppEvent) instances to
 * the main UI event loop. Callers must be attached to the D runtime
 * ($(D Thread.getThis() !is null)). Background-thread sends post a single SDL
 * wake event when the main thread is idle or waiting; main-thread sends never
 * emit wake events. Raw input events (including $(D AppEvent.Kind.mouseMotion))
 * are never merged.
 */
struct MessageBus {
  @disable this();

  /**
   * Constructs a $(D MessageBus) with a dedicated synchronization monitor.
   *
   * Params:
   *   lockObj = Object used as the monitor for $(D synchronized) blocks.
   */
  this(Object lockObj) {
    assert(lockObj !is null);
    this.lock = lockObj;
    this.queue.reserve(initialCapacity);
    if (fStatsEnabled) {
      const long now = ticksToNSecs(MonoTime.currTime.ticks);
      totalStartNs = now;
      totalRunning = true;
      windowStartNs = now;
    }
  }

  invariant {
    assert(lock !is null);
    assert(queue.capacity > 0);
  }

  /// Marks the calling D-attached thread as the main UI loop thread so
  /// main-thread sends do not emit redundant SDL_WAKE events.
  void bindMainThread() {
    Thread current = Thread.getThis();
    assert(current !is null, "MessageBus requires a D-attached thread");
    const ThreadID tid = current.id;
    synchronized (lock) {
      mainThreadId = tid;
      hasMainThread = true;
    }
  }

  /// Clears main-thread binding on event loop exit.
  void unbindMainThread() {
    synchronized (lock) {
      hasMainThread = false;
    }
  }

  /**
   * Enqueues an event in strict FIFO order and signals the UI thread when
   * called from a background D-attached thread.
   *
   * Params:
   *   ev = The event to enqueue.
   */
  void send(AppEvent ev) {
    bool needWake = false;
    int delegate() wakeCb = null;
    Thread current = Thread.getThis();
    assert(current !is null, "MessageBus requires a D-attached thread");
    const ThreadID callerId = current.id;
    synchronized (lock) {
      const bool isMain = hasMainThread && callerId == mainThreadId;
      bool allowedToSend = true;
      if (ev.noRepeat && isDuplicateNoRepeat(ev)) {
        allowedToSend = false;
      }
      if (allowedToSend) {
        pendingKindCounts[ev.kind]++;
        queue.push(move(ev));
        if (!isMain && !wakeSent) {
          wakeSent = true;
          needWake = true;
          wakeCb = wakeFn;
        }
      }
      recordEventStats(allowedToSend);
    }
    if (needWake) {
      const int rc = wakeCb !is null
        ? wakeCb()
        : yguilib_sdl3_send_wake_event();
      if (rc != 0) {
        synchronized (lock) {
          wakeSent = false;
        }
        import std.logger : warning;

        warning("MessageBus: failed to push SDL wake event");
      }
    }
  }

  /**
   * Dequeues the next pending event in FIFO order, or returns an empty
   * $(D Nullable) if the queue is empty.
   */
  Nullable!AppEvent get() {
    synchronized (lock) {
      Nullable!AppEvent ev = queue.tryPopFront();
      if (ev.isNull) {
        return ev;
      }
      const AppEvent.Kind kind = ev.get().kind;
      assert(pendingKindCounts[kind] > 0);
      pendingKindCounts[kind]--;
      if (queue.empty && queue.capacity > maxIdleCapacity) {
        queue.releaseMemory();
        queue.reserve(initialCapacity);
      }
      return ev;
    }
  }

  /// Returns $(D true) if there are pending events awaiting retrieval.
  bool hasPending() {
    synchronized (lock) {
      return !queue.empty;
    }
  }

  /// Atomically checks whether the queue is empty and arms wakeup signaling
  /// before the main thread blocks in SDL_WaitEventTimeout.
  /// Returns $(D true) if empty (safe to wait), $(D false) if events exist.
  bool prepareToWait() {
    synchronized (lock) {
      if (!queue.empty) {
        return false;
      }
      wakeSent = false;
      return true;
    }
  }

  @property size_t length() {
    synchronized (lock) {
      return queue.length;
    }
  }

  @property size_t capacity() {
    synchronized (lock) {
      return queue.capacity;
    }
  }

  /// Sets a custom wake event sender delegate for deterministic testing.
  /// Passing $(D null) restores $(D yguilib_sdl3_send_wake_event).
  void wakeSender(int delegate() fn) {
    synchronized (lock) {
      wakeFn = fn;
    }
  }

  /// Sets a custom nanosecond clock delegate for deterministic testing.
  /// Passing $(D null) restores the default monotonic clock.
  void clock(long delegate() fn) {
    synchronized (lock) {
      clockFn = fn;
      const long now = nowNs();
      totalStartNs = now;
      totalElapsedNs = 0;
      windowStartNs = now;
      currentWindowCount = 0;
      maxEventsPerSecond = 0;
      postedCount = 0;
      suppressedCount = 0;
    }
  }

  /**
   * Enables or disables event queue statistics recording at runtime.
   */
  @property void statsEnabled(bool enabled) {
    synchronized (lock) {
      if (enabled == fStatsEnabled) {
        return;
      }
      fStatsEnabled = enabled;
      const long now = nowNs();
      if (enabled) {
        totalStartNs = now;
        totalRunning = true;
        currentWindowCount = 0;
        windowStartNs = now;
      } else {
        if (totalRunning) {
          totalElapsedNs += now - totalStartNs;
          totalRunning = false;
        }
        flushWindowMax();
      }
    }
  }

  /**
   * Returns $(D true) if event queue statistics recording is active.
   */
  @property bool statsEnabled() {
    synchronized (lock) {
      return fStatsEnabled;
    }
  }

  /**
   * Returns a thread-safe snapshot of the recorded event queue statistics.
   */
  EventQueueStats queueStats() {
    synchronized (lock) {
      const long now = nowNs();
      const long totalNs = totalRunning
        ? totalElapsedNs + (now - totalStartNs)
        : totalElapsedNs;
      const ulong peak = currentWindowCount > maxEventsPerSecond
        ? currentWindowCount
        : maxEventsPerSecond;
      const double elapsedSec = totalNs / 1_000_000_000.0;
      const double avgPerSec = elapsedSec > 0.0
        ? cast(double) postedCount / elapsedSec
        : 0.0;
      return EventQueueStats(
        postedCount,
        suppressedCount,
        peak,
        avgPerSec,
        elapsedSec,
      );
    }
  }

  /**
   * Logs recorded event queue statistics via $(D std.logger).
   */
  void logStats() {
    bool shouldLog = false;
    synchronized (lock) {
      shouldLog = fStatsEnabled || postedCount > 0 || suppressedCount > 0;
    }
    if (!shouldLog) {
      return;
    }
    import std.logger : infof;
    const stats = queueStats();
    infof(
      "MessageBus stats: posted=%s, suppressed=%s, avg=%.2f/s, max=%s/s, " ~
      "duration=%.2fs",
      stats.postedCount,
      stats.suppressedCount,
      stats.avgEventsPerSecond,
      stats.maxEventsPerSecond,
      stats.elapsedSeconds,
    );
  }

private:
  static bool isIdempotentNoRepeatKind(AppEvent.Kind k) {
    return k == AppEvent.Kind.update;
  }

  bool isDuplicateNoRepeat(in AppEvent ev) const {
    if (queue.empty) {
      return false;
    }
    if (isIdempotentNoRepeatKind(ev.kind)) {
      return pendingKindCounts[ev.kind] > 0;
    }
    foreach (const ref item; queue) {
      if (item.equalsContent(ev)) {
        return true;
      }
    }
    return false;
  }

  long nowNs() const {
    return clockFn !is null
      ? clockFn()
      : ticksToNSecs(MonoTime.currTime.ticks);
  }

  void recordEventStats(bool posted) {
    if (!fStatsEnabled) {
      return;
    }
    const long now = nowNs();
    if (now - windowStartNs >= oneSecondNs) {
      flushWindowMax();
      windowStartNs = now;
    }
    if (posted) {
      postedCount++;
      currentWindowCount++;
    } else {
      suppressedCount++;
    }
  }

  void flushWindowMax() {
    if (currentWindowCount > maxEventsPerSecond) {
      maxEventsPerSecond = currentWindowCount;
    }
    currentWindowCount = 0;
  }

  enum size_t initialCapacity = 64;
  enum size_t maxIdleCapacity = initialCapacity * 4;
  RingBuffer!AppEvent queue;
  size_t[AppEvent.Kind.max + 1] pendingKindCounts;
  bool wakeSent = false;
  bool hasMainThread = false;
  ThreadID mainThreadId;
  Object lock;

  enum long oneSecondNs = 1_000_000_000L;
  debug {
    bool fStatsEnabled = true;
  } else {
    bool fStatsEnabled = false;
  }
  long delegate() clockFn = null;
  int delegate() wakeFn = null;
  ulong postedCount = 0;
  ulong suppressedCount = 0;
  ulong maxEventsPerSecond = 0;
  ulong currentWindowCount = 0;
  long totalStartNs = 0;
  long totalElapsedNs = 0;
  bool totalRunning = false;
  long windowStartNs = 0;
}

// Verifies MessageBus event queueing, retrieval, and ring buffer reuse.
unittest {
  MessageBus bus = MessageBus(new Object);
  assert(!bus.hasPending());
  assert(bus.get().isNull);

  bus.send(AppEvent.userEvent(AppEvent.UserData(1)));
  bus.send(AppEvent.userEvent(AppEvent.UserData(2)));
  assert(bus.hasPending());

  auto ev1 = bus.get();
  assert(!ev1.isNull && ev1.get().user.eventId == 1);
  assert(bus.hasPending());

  auto ev2 = bus.get();
  assert(!ev2.isNull && ev2.get().user.eventId == 2);
  assert(!bus.hasPending());
  assert(bus.get().isNull);

  // Re-enqueue to verify queue reuse without reallocation
  bus.send(AppEvent.userEvent(AppEvent.UserData(3)));
  assert(bus.hasPending());
  auto ev3 = bus.get();
  assert(!ev3.isNull && ev3.get().user.eventId == 3);
  assert(!bus.hasPending());
}

// Verifies noRepeat false allows duplicates and noRepeat true deduplicates
// across the entire ring buffer (even behind mouseMotion and mixed flags).
unittest {
  MessageBus bus = MessageBus(new Object);
  bus.send(AppEvent(AppEvent.Kind.windowRedraw));
  bus.send(AppEvent(AppEvent.Kind.windowRedraw));
  assert(bus.length == 2);

  while (!bus.get().isNull) {}

  // Send motion, then update (without noRepeat), then motion, then
  // makeNoRepeat(update): must suppress the duplicate update!
  bus.send(AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 10.0f, 20.0f)
  ));
  bus.send(AppEvent(AppEvent.Kind.update));
  bus.send(AppEvent.mouseEvent(
    AppEvent.Kind.mouseMotion,
    AppEvent.MouseData(1, 30.0f, 40.0f)
  ));
  bus.send(AppEvent.makeNoRepeat(AppEvent.Kind.update));
  bus.send(AppEvent.makeNoRepeat(AppEvent.Kind.update));
  assert(bus.length == 3);

  // Payloaded noRepeat deduplication behind other events
  bus.send(AppEvent.makeNoRepeat(AppEvent.Kind.windowRedraw));
  bus.send(AppEvent.makeNoRepeat(AppEvent.Kind.windowRedraw));
  assert(bus.length == 4);
}

// Verifies ring buffer constant capacity over sustained unmerged mouseMotion
// traffic and strict FIFO preservation of curved coordinates.
unittest {
  MessageBus bus = MessageBus(new Object);
  const size_t initCap = bus.capacity();

  // Seed 4 events so queue never empties during continuous traffic
  foreach (i; 0 .. 4) {
    bus.send(AppEvent.mouseEvent(
      AppEvent.Kind.mouseMotion,
      AppEvent.MouseData(1, cast(float) i, cast(float) (i * 2))
    ));
  }

  foreach (i; 4 .. 10_004) {
    auto popped = bus.get();
    assert(!popped.isNull);
    assert(popped.get().kind == AppEvent.Kind.mouseMotion);
    assert(popped.get().mouse.x == cast(float) (i - 4));
    assert(popped.get().mouse.y == cast(float) ((i - 4) * 2));

    bus.send(AppEvent.mouseEvent(
      AppEvent.Kind.mouseMotion,
      AppEvent.MouseData(1, cast(float) i, cast(float) (i * 2))
    ));
  }

  assert(bus.capacity() == initCap);
  assert(bus.length == 4);
}

// Verifies grow() preserves FIFO order across wrap-around and prepareToWait().
unittest {
  MessageBus bus = MessageBus(new Object);
  bus.bindMainThread();

  // Main-thread send must not arm wakeSent
  bus.send(AppEvent.userEvent(AppEvent.UserData(1)));
  assert(!bus.wakeSent);
  assert(!bus.prepareToWait());
  assert(!bus.get().isNull);
  assert(bus.prepareToWait());

  // Unbound / background send arms wakeSent when wake succeeds
  bus.wakeSender(() => 0);
  bus.unbindMainThread();
  bus.send(AppEvent.userEvent(AppEvent.UserData(2)));
  assert(bus.wakeSent);
  assert(!bus.prepareToWait());
  assert(!bus.get().isNull);
  assert(bus.prepareToWait());
  assert(!bus.wakeSent);

  // Wake failure resets wakeSent so subsequent sends retry waking
  int wakeCalls = 0;
  bus.wakeSender(() {
    wakeCalls++;
    return -1;
  });
  bus.send(AppEvent.userEvent(AppEvent.UserData(3)));
  assert(wakeCalls == 1);
  assert(!bus.wakeSent);
  bus.send(AppEvent.userEvent(AppEvent.UserData(4)));
  assert(wakeCalls == 2);
  assert(!bus.wakeSent);
  while (!bus.get().isNull) {}
  assert(bus.prepareToWait());
  bus.wakeSender(null);

  // Force wrap-around and grow past initialCapacity
  foreach (i; 0 .. 40) {
    bus.send(AppEvent.userEvent(AppEvent.UserData(cast(uint) i)));
    auto ev = bus.get();
    assert(!ev.isNull && ev.get().user.eventId == i);
  }
  foreach (i; 0 .. 100) {
    bus.send(AppEvent.userEvent(AppEvent.UserData(cast(uint) i)));
  }
  assert(bus.capacity() >= 128);
  foreach (i; 0 .. 100) {
    auto ev = bus.get();
    assert(!ev.isNull && ev.get().user.eventId == i);
  }
  assert(!bus.hasPending());
}

// Verifies event queue stats counting, noRepeat suppression, and toggling.
unittest {
  MessageBus bus = MessageBus(new Object);
  bus.statsEnabled(true);
  assert(bus.statsEnabled);

  bus.send(AppEvent.makeNoRepeat(AppEvent.Kind.update));
  bus.send(AppEvent.makeNoRepeat(AppEvent.Kind.update));
  bus.send(AppEvent.userEvent(AppEvent.UserData(1)));

  auto stats = bus.queueStats();
  assert(stats.postedCount == 2);
  assert(stats.suppressedCount == 1);
  assert(stats.maxEventsPerSecond == 2);

  bus.statsEnabled(false);
  assert(!bus.statsEnabled);
  bus.send(AppEvent.userEvent(AppEvent.UserData(2)));
  stats = bus.queueStats();
  assert(stats.postedCount == 2);

  bus.statsEnabled(true);
  bus.send(AppEvent.userEvent(AppEvent.UserData(3)));
  stats = bus.queueStats();
  assert(stats.postedCount == 3);
  bus.logStats();
}

// Verifies 1-second window rollover for max and avg events per second
// using an injectable clock delegate.
unittest {
  long fakeNow = 1_000_000_000L;
  MessageBus bus = MessageBus(new Object);
  bus.clock(() => fakeNow);
  bus.statsEnabled(true);

  bus.send(AppEvent.userEvent(AppEvent.UserData(1)));
  bus.send(AppEvent.userEvent(AppEvent.UserData(2)));
  bus.send(AppEvent.userEvent(AppEvent.UserData(3)));

  fakeNow += 1_050_000_000L;
  bus.send(AppEvent.userEvent(AppEvent.UserData(4)));

  const stats = bus.queueStats();
  assert(stats.postedCount == 4);
  assert(stats.maxEventsPerSecond == 3);
  assert(stats.elapsedSeconds >= 1.0);
  assert(stats.avgEventsPerSecond > 0.0 && stats.avgEventsPerSecond <= 4.0);
}

// Verifies non-idempotent noRepeat deduplication, windowId distinction on
// windowRedraw, and shrink-when-empty after burst capacity.
unittest {
  MessageBus bus = MessageBus(new Object);

  // Non-idempotent Kind.user with noRepeat deduplicates matching payloads
  // while preserving distinct payloads.
  auto u1 = AppEvent.makeNoRepeat(AppEvent.Kind.user);
  u1.user.eventId = 10;
  auto u1Dup = AppEvent.makeNoRepeat(AppEvent.Kind.user);
  u1Dup.user.eventId = 10;
  auto u2 = AppEvent.makeNoRepeat(AppEvent.Kind.user);
  u2.user.eventId = 20;

  bus.send(u1);
  bus.send(u1Dup);
  bus.send(u2);
  assert(bus.length == 2);

  // windowRedraw with different windowId values must not collapse
  auto r1 = AppEvent.makeNoRepeat(AppEvent.Kind.windowRedraw);
  r1.window.windowId = 1;
  auto r2 = AppEvent.makeNoRepeat(AppEvent.Kind.windowRedraw);
  r2.window.windowId = 2;
  auto r1Dup = AppEvent.makeNoRepeat(AppEvent.Kind.windowRedraw);
  r1Dup.window.windowId = 1;
  bus.send(r1);
  bus.send(r2);
  bus.send(r1Dup);
  assert(bus.length == 4);

  while (!bus.get().isNull) {}

  // Burst > 4 * initialCapacity (256), then drain -> shrinks back to 64
  foreach (i; 0 .. 300) {
    bus.send(AppEvent.userEvent(AppEvent.UserData(cast(uint) i)));
  }
  assert(bus.capacity > 256);
  while (!bus.get().isNull) {}
  assert(bus.capacity == 64);
}

// Verifies multi-producer / single-consumer thread safety across D threads.
unittest {
  import core.thread : Thread;

  MessageBus bus = MessageBus(new Object);
  bus.bindMainThread();

  enum size_t producerCount = 4;
  enum size_t perProducer = 250;
  Thread[producerCount] threads;

  Thread makeProducer(uint baseId) {
    return new Thread(() {
      foreach (i; 0 .. perProducer) {
        bus.send(AppEvent.userEvent(AppEvent.UserData(baseId + cast(uint) i)));
      }
    });
  }

  foreach (p; 0 .. producerCount) {
    threads[p] = makeProducer(cast(uint) (p * perProducer));
    threads[p].start();
  }

  size_t consumed = 0;
  bool[producerCount * perProducer] seen;
  while (consumed < producerCount * perProducer) {
    auto ev = bus.get();
    if (!ev.isNull) {
      const uint id = ev.get().user.eventId;
      assert(!seen[id]);
      seen[id] = true;
      consumed++;
    } else {
      Thread.yield();
    }
  }

  foreach (t; threads) {
    t.join();
  }
  assert(!bus.hasPending());
}
