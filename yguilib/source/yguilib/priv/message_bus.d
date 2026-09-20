module yguilib.priv.message_bus;

import yguilib.events;
import yguilib.clibs.sdl3;
import std.typecons : Nullable;

struct MessageBus {
  @disable this();
  this(Object lockObj) {
    assert(lockObj !is null);
    this.lock = lockObj;
  }

  invariant {
    assert(lock !is null);
  }

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

  bool hasPending() {
    synchronized (lock) {
      return head < events.length;
    }
  }

  /// make sure we resume if bus not empty
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
