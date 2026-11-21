module yguilib.events.internal.message_bus;

package(yguilib):

import core.lifetime : move;
import core.thread : Thread, ThreadID;
import std.typecons : Nullable;
import yguilib.allochelpers : RingBuffer;
import yguilib.clibs.sdl3;
import yguilib.events : AppEvent;
import yguilib.timers : StopWatchNs;

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
 * Allows background threads to post $(D AppEvent) instances to the main UI
 * event loop. Background-thread sends post a single SDL wake event when the
 * main thread is idle or waiting; main-thread sends never emit wake events.
 * Raw input events (including $(D AppEvent.Kind.mouseMotion)) are never merged.
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
      fTotalWatch.start();
      fWindowWatch.start();
    }
  }

  invariant {
    assert(lock !is null);
  }

  /// Marks the calling thread as the main UI loop thread so main-thread
  /// sends do not emit redundant SDL_WAKE events.
  void bindMainThread() {
    const ThreadID tid = Thread.getThis().id;
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
   * called from a background thread.
   *
   * Params:
   *   ev = The event to enqueue.
   */
  void send(AppEvent ev) {
    bool needWake = false;
    const ThreadID callerId = Thread.getThis().id;
    synchronized (lock) {
      if (queue.capacity == 0) {
        queue.reserve(initialCapacity);
      }
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
        }
      }
      recordEventStats(allowedToSend);
    }
    if (needWake) {
      yguilib_sdl3_send_wake_event();
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

  size_t length() {
    synchronized (lock) {
      return queue.length;
    }
  }

  size_t capacity() {
    synchronized (lock) {
      return queue.capacity;
    }
  }

  /**
   * Enables or disables event queue statistics recording at runtime.
   */
  void setStatsEnabled(bool enabled) {
    synchronized (lock) {
      if (enabled == fStatsEnabled) {
        return;
      }
      fStatsEnabled = enabled;
      if (enabled) {
        fTotalWatch.start();
        fCurrentWindowCount = 0;
        fWindowWatch.reset();
        fWindowWatch.start();
      } else {
        fTotalWatch.stop();
        fWindowWatch.stop();
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
  EventQueueStats getStats() {
    synchronized (lock) {
      fTotalWatch.update();
      fWindowWatch.update();
      const ulong peak = fCurrentWindowCount > fMaxEventsPerSecond
        ? fCurrentWindowCount
        : fMaxEventsPerSecond;
      const double elapsedSec = fTotalWatch.elapsed() / 1_000_000_000.0;
      const double avgPerSec = elapsedSec > 0.0
        ? cast(double) fPostedCount / elapsedSec
        : 0.0;
      return EventQueueStats(
        fPostedCount,
        fSuppressedCount,
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
      shouldLog = fStatsEnabled || fPostedCount > 0 || fSuppressedCount > 0;
    }
    if (!shouldLog) {
      return;
    }
    import std.logger : infof;
    const stats = getStats();
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
    return k == AppEvent.Kind.update || k == AppEvent.Kind.windowRedraw;
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

  void recordEventStats(bool posted) {
    if (!fStatsEnabled) {
      return;
    }
    fWindowWatch.update();
    if (fWindowWatch.elapsed() >= oneSecondNs) {
      flushWindowMax();
      fWindowWatch.reset();
      fWindowWatch.start();
    }
    if (posted) {
      fPostedCount++;
      fCurrentWindowCount++;
    } else {
      fSuppressedCount++;
    }
  }

  void flushWindowMax() {
    if (fCurrentWindowCount > fMaxEventsPerSecond) {
      fMaxEventsPerSecond = fCurrentWindowCount;
    }
    fCurrentWindowCount = 0;
  }

  enum size_t initialCapacity = 64;
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
  ulong fPostedCount = 0;
  ulong fSuppressedCount = 0;
  ulong fMaxEventsPerSecond = 0;
  ulong fCurrentWindowCount = 0;
  StopWatchNs fTotalWatch;
  StopWatchNs fWindowWatch;
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

  // Unbound / background send arms wakeSent
  bus.unbindMainThread();
  bus.send(AppEvent.userEvent(AppEvent.UserData(2)));
  assert(bus.wakeSent);
  assert(!bus.prepareToWait());
  assert(!bus.get().isNull);
  assert(bus.prepareToWait());
  assert(!bus.wakeSent);

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
  bus.setStatsEnabled(true);
  assert(bus.statsEnabled);

  bus.send(AppEvent.makeNoRepeat(AppEvent.Kind.update));
  bus.send(AppEvent.makeNoRepeat(AppEvent.Kind.update));
  bus.send(AppEvent.userEvent(AppEvent.UserData(1)));

  auto stats = bus.getStats();
  assert(stats.postedCount == 2);
  assert(stats.suppressedCount == 1);
  assert(stats.maxEventsPerSecond == 2);

  bus.setStatsEnabled(false);
  assert(!bus.statsEnabled);
  bus.send(AppEvent.userEvent(AppEvent.UserData(2)));
  stats = bus.getStats();
  assert(stats.postedCount == 2);

  bus.setStatsEnabled(true);
  bus.send(AppEvent.userEvent(AppEvent.UserData(3)));
  stats = bus.getStats();
  assert(stats.postedCount == 3);
  bus.logStats();
}

// Verifies 1-second window rollover for max and avg events per second.
unittest {
  import core.thread : Thread;
  import core.time : msecs;

  MessageBus bus = MessageBus(new Object);
  bus.setStatsEnabled(true);

  bus.send(AppEvent.userEvent(AppEvent.UserData(1)));
  bus.send(AppEvent.userEvent(AppEvent.UserData(2)));
  bus.send(AppEvent.userEvent(AppEvent.UserData(3)));

  Thread.sleep(1050.msecs);
  bus.send(AppEvent.userEvent(AppEvent.UserData(4)));

  const stats = bus.getStats();
  assert(stats.postedCount == 4);
  assert(stats.maxEventsPerSecond == 3);
  assert(stats.elapsedSeconds >= 1.0);
  assert(stats.avgEventsPerSecond > 0.0 && stats.avgEventsPerSecond <= 4.0);
}
