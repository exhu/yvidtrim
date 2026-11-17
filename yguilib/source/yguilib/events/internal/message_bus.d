module yguilib.events.internal.message_bus;

package(yguilib):

import std.typecons : Nullable;
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
 * Thread-safe FIFO event queue for cross-thread communication with the UI.
 *
 * Allows background threads to post $(D AppEvent) instances to the main UI
 * event loop. Whenever an event is enqueued, an SDL wake event is sent to wake
 * the main thread if it is blocked waiting for events.
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
    if (fStatsEnabled) {
      fTotalWatch.start();
      fWindowWatch.start();
    }
  }

  invariant {
    assert(lock !is null);
  }

  /**
   * Enqueues an event and signals the UI thread event loop.
   *
   * Posts an SDL wake event if a wake signal is not already in flight.
   *
   * Params:
   *   ev = The event to enqueue.
   */
  void send(AppEvent ev) {
    bool needWake = false;
    synchronized (lock) {
      resetIfEmpty();
      bool allowedToSend = true;
      if (ev.noRepeat && !isQueueEmpty() && (ev == events[head])) {
        allowedToSend = false;
      }
      if (allowedToSend) {
        events ~= ev;
        if (!wakeSent) {
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
      resetIfEmpty();
      if (head >= events.length) {
        return Nullable!AppEvent.init;
      }
      auto ev = events[head++];
      resetIfEmpty();
      return Nullable!AppEvent(ev);
    }
  }

  /**
   * Returns $(D true) if there are pending events awaiting retrieval.
   */
  bool hasPending() {
    synchronized (lock) {
      return head < events.length;
    }
  }

  /**
   * Ensures an SDL wake event is sent if there are pending unconsumed events.
   *
   * Used to resume the UI event loop when events remain queued.
   */
  void ensureWake() {
    bool needWake = false;
    synchronized (lock) {
      if (head < events.length) {
        wakeSent = true;
        needWake = true;
      }
    }
    if (needWake) {
      yguilib_sdl3_send_wake_event();
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
  void resetIfEmpty() {
    if (head >= events.length) {
      events.length = 0;
      head = 0;
      wakeSent = false;
    }
  }

  bool isQueueEmpty() {
    return head >= events.length;
  }

  AppEvent[] events;
  size_t head = 0;
  bool wakeSent = false;
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

// Verifies MessageBus event queueing, retrieval, and buffer reuse.
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

// test noRepeat false
unittest {
  MessageBus bus = MessageBus(new Object);
  bus.send(AppEvent(AppEvent.Kind.updateUiLayer));
  bus.send(AppEvent(AppEvent.Kind.updateUiLayer));
  assert(bus.events.length == 2);
}

// test noRepeat true
unittest {
  MessageBus bus = MessageBus(new Object);
  bus.send(AppEvent.makeNoRepeat(AppEvent.Kind.updateUiLayer));
  bus.send(AppEvent.makeNoRepeat(AppEvent.Kind.updateUiLayer));
  assert(bus.events.length == 1);
}

// Verifies event queue stats counting, noRepeat suppression, and toggling.
unittest {
  MessageBus bus = MessageBus(new Object);
  bus.setStatsEnabled(true);
  assert(bus.statsEnabled);

  bus.send(AppEvent.makeNoRepeat(AppEvent.Kind.updateUiLayer));
  bus.send(AppEvent.makeNoRepeat(AppEvent.Kind.updateUiLayer));
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
