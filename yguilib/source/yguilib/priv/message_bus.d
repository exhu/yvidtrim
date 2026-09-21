module yguilib.priv.message_bus;

import yguilib.events;
import yguilib.clibs.sdl3;
import std.typecons : Nullable;

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
      events ~= ev;
      if (!wakeSent) {
        wakeSent = true;
        needWake = true;
      }
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

private:
  void resetIfEmpty() {
    if (head >= events.length) {
      events.length = 0;
      head = 0;
      wakeSent = false;
    }
  }

  AppEvent[] events;
  size_t head = 0;
  bool wakeSent = false;
  Object lock;
}

// Verifies MessageBus event queueing, retrieval, and buffer reuse.
unittest {
  MessageBus bus = MessageBus(new Object);
  assert(!bus.hasPending());
  assert(bus.get().isNull);

  bus.send(AppEvent(AppEvent.Kind.user, 1));
  bus.send(AppEvent(AppEvent.Kind.user, 2));
  assert(bus.hasPending());

  auto ev1 = bus.get();
  assert(!ev1.isNull && ev1.get().eventId == 1);
  assert(bus.hasPending());

  auto ev2 = bus.get();
  assert(!ev2.isNull && ev2.get().eventId == 2);
  assert(!bus.hasPending());
  assert(bus.get().isNull);

  // Re-enqueue to verify queue reuse without reallocation
  bus.send(AppEvent(AppEvent.Kind.user, 3));
  assert(bus.hasPending());
  auto ev3 = bus.get();
  assert(!ev3.isNull && ev3.get().eventId == 3);
  assert(!bus.hasPending());
}
