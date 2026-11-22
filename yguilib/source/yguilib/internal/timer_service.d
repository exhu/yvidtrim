module yguilib.internal.timer_service;

package(yguilib):

import core.time : MonoTime, ticksToNSecs;
import yguilib.allochelpers : ReusableArray, SmallBuffer;
import yguilib.timers : TimerId, TimerIntervalMs, TimerMode, invalidTimerId;

struct TimerEntry {
  TimerId id = invalidTimerId;
  long periodNs = 0;
  long nextFireNs = 0;
  long lastFireNs = 0;
  TimerMode mode = TimerMode.repeat;
  Object owner = null;
  bool active = false;
}

/// Manages wall-clock timers bound to owners.
struct TimerService {
  void setClock(long delegate() clock) {
    clockFn = clock;
  }

  long nowNs() const {
    if (clockFn !is null) {
      return clockFn();
    }
    return ticksToNSecs(MonoTime.currTime.ticks);
  }

  TimerId startTimer(
    Object owner,
    uint intervalMs,
    TimerMode mode
  ) {
    assert(owner !is null, "Timer owner must not be null");
    TimerEntry entry;
    entry.owner = owner;
    return addEntry(entry, intervalMs, mode);
  }

  void stopTimer(TimerId id) {
    if (id == invalidTimerId) {
      return;
    }
    foreach (ref e; entries[]) {
      if (e.active && e.id == id) {
        deactivateEntry(e);
        break;
      }
    }
    compactIfIdle();
  }

  bool isTimerActive(TimerId id) const {
    if (id == invalidTimerId) {
      return false;
    }
    foreach (const ref e; entries[]) {
      if (e.active && e.id == id) {
        return true;
      }
    }
    return false;
  }

  void stopTimersForOwner(Object owner) {
    if (owner is null) {
      return;
    }
    foreach (ref e; entries[]) {
      if (e.active && e.owner is owner) {
        deactivateEntry(e);
      }
    }
    compactIfIdle();
  }

  int nextWaitTimeoutMs(long now) const {
    bool hasActive = false;
    long earliestNs = 0;
    foreach (const ref e; entries[]) {
      if (!e.active) {
        continue;
      }
      if (!hasActive || e.nextFireNs < earliestNs) {
        earliestNs = e.nextFireNs;
        hasActive = true;
      }
    }
    if (!hasActive) {
      return -1;
    }
    if (earliestNs <= now) {
      return 0;
    }
    import std.algorithm.comparison : min;
    const long diffNs = earliestNs - now;
    const long ceilMs = (diffNs + 999_999L) / 1_000_000L;
    return cast(int) min(cast(long) int.max, ceilMs);
  }

  bool hasDueTimers(long now) const {
    foreach (const ref e; entries[]) {
      if (e.active && e.nextFireNs <= now) {
        return true;
      }
    }
    return false;
  }

  void fireDueTimers(
    long now,
    scope void delegate(TimerEntry entry, float dt) onFire
  ) {
    assert(onFire !is null);
    SmallBuffer!(TimerId, 32) dueIds;
    collectDueIds(now, dueIds);
    if (dueIds.empty) {
      return;
    }

    firingDepth++;
    scope (exit) {
      firingDepth--;
      compactIfIdle();
    }

    foreach (id; dueIds[]) {
      ptrdiff_t idx = findActiveIndex(id);
      if (idx < 0 || entries[idx].nextFireNs > now) {
        continue;
      }
      fireEntryAt(cast(size_t) idx, now, onFire);
    }
  }

  size_t activeCount() const {
    size_t count = 0;
    foreach (const ref e; entries[]) {
      if (e.active) {
        count++;
      }
    }
    return count;
  }

private:
  TimerId addEntry(TimerEntry entry, uint intervalMs, TimerMode mode) {
    import std.algorithm.comparison : max;
    const uint effectiveMs = (mode == TimerMode.repeat)
      ? max(1u, intervalMs)
      : intervalMs;
    const long now = nowNs();
    const long periodNs = cast(long) effectiveMs * 1_000_000L;

    entry.id = allocateId();
    entry.periodNs = periodNs;
    entry.lastFireNs = now;
    entry.nextFireNs = now + periodNs;
    entry.mode = mode;
    entry.active = true;
    entries.push(entry);
    return entry.id;
  }

  TimerId allocateId() {
    TimerId id = nextId++;
    if (nextId == invalidTimerId) {
      nextId = 1;
    }
    if (id == invalidTimerId) {
      id = nextId++;
    }
    return id;
  }

  void collectDueIds(long now, ref SmallBuffer!(TimerId, 32) dueIds) const {
    foreach (const ref e; entries[]) {
      if (e.active && e.nextFireNs <= now) {
        dueIds.push(e.id);
      }
    }
  }

  ptrdiff_t findActiveIndex(TimerId id) const {
    foreach (i, const ref e; entries[]) {
      if (e.active && e.id == id) {
        return cast(ptrdiff_t) i;
      }
    }
    return -1;
  }

  void fireEntryAt(
    size_t idx,
    long now,
    scope void delegate(TimerEntry entry, float dt) onFire
  ) {
    TimerEntry copy = entries[idx];
    const long diffNs = now > entries[idx].lastFireNs
      ? now - entries[idx].lastFireNs
      : 0;
    const float periodSec = cast(float) entries[idx].periodNs /
      1_000_000_000.0f;
    import std.algorithm.comparison : max, min;
    const float maxDt = max(0.1f, periodSec * 2.0f);
    const float dt = min(maxDt, cast(float) diffNs / 1_000_000_000.0f);

    entries[idx].lastFireNs = now;
    if (entries[idx].mode == TimerMode.oneShot) {
      deactivateEntry(entries[idx]);
    } else {
      long next = entries[idx].nextFireNs + entries[idx].periodNs;
      if (next <= now) {
        next = now + entries[idx].periodNs;
      }
      entries[idx].nextFireNs = next;
    }

    onFire(copy, dt);
  }

  static void deactivateEntry(ref TimerEntry e) {
    e.active = false;
    e.owner = null;
  }

  void compactIfIdle() {
    if (firingDepth > 0) {
      return;
    }
    entries.compact((const ref TimerEntry e) => e.active);
  }

  ReusableArray!TimerEntry entries;
  TimerId nextId = 1;
  uint firingDepth = 0;
  long delegate() clockFn = null;
}

// Verifies TimerService idle timeout, ceiling rounding, and firing semantics.
unittest {
  import std.math.operations : isClose;

  long fakeNowNs = 1_000_000_000L;
  TimerService svc;
  svc.setClock(() => fakeNowNs);

  // Idle when empty -> -1
  assert(svc.nextWaitTimeoutMs(fakeNowNs) == -1);
  assert(!svc.hasDueTimers(fakeNowNs));

  // Register a 16ms repeat timer and a 500ms one-shot timer
  auto repeatOwner = new Object();
  auto oneShotOwner = new Object();
  int repeatCalls = 0;
  float lastRepeatDt = 0.0f;
  int oneShotCalls = 0;

  TimerId idRepeat = svc.startTimer(
    repeatOwner,
    TimerIntervalMs.fps60,
    TimerMode.repeat
  );
  TimerId idOneShot = svc.startTimer(oneShotOwner, 500, TimerMode.oneShot);

  assert(svc.isTimerActive(idRepeat));
  assert(svc.isTimerActive(idOneShot));
  assert(svc.nextWaitTimeoutMs(fakeNowNs) == 16);

  // Sub-millisecond remaining rounds UP to 1 ms to prevent spin
  fakeNowNs += 15_100_000L;
  assert(svc.nextWaitTimeoutMs(fakeNowNs) == 1);
  assert(!svc.hasDueTimers(fakeNowNs));

  // Cross 16 ms deadline: only repeat timer fires
  fakeNowNs += 900_000L;
  assert(svc.hasDueTimers(fakeNowNs));
  assert(svc.nextWaitTimeoutMs(fakeNowNs) == 0);
  svc.fireDueTimers(fakeNowNs, (TimerEntry e, float dt) {
    if (e.owner is repeatOwner) {
      repeatCalls++;
      lastRepeatDt = dt;
    } else if (e.owner is oneShotOwner) {
      oneShotCalls++;
    }
  });
  assert(repeatCalls == 1);
  assert(isClose(lastRepeatDt, 0.016f, 0.0001f));
  assert(oneShotCalls == 0);
  assert(svc.nextWaitTimeoutMs(fakeNowNs) == 16);

  // Simulate VSync overshoot (20 ms elapsed instead of 16 ms):
  // next deadline anchors to previous deadline + 16 ms -> 12 ms remaining
  fakeNowNs += 20_000_000L;
  svc.fireDueTimers(fakeNowNs, (TimerEntry e, float dt) {
    if (e.owner is repeatOwner) {
      repeatCalls++;
      lastRepeatDt = dt;
    } else if (e.owner is oneShotOwner) {
      oneShotCalls++;
    }
  });
  assert(repeatCalls == 2);
  assert(isClose(lastRepeatDt, 0.020f, 0.0001f));
  assert(svc.nextWaitTimeoutMs(fakeNowNs) == 12);

  // Lag clamp when behind by > 1 period (no spiral of death)
  fakeNowNs += 500_000_000L;
  svc.fireDueTimers(fakeNowNs, (TimerEntry e, float dt) {
    if (e.owner is repeatOwner) {
      repeatCalls++;
      lastRepeatDt = dt;
    } else if (e.owner is oneShotOwner) {
      oneShotCalls++;
    }
  });
  assert(repeatCalls == 3);
  assert(oneShotCalls == 1);
  assert(!svc.isTimerActive(idOneShot));
  // Clamped to now + 16 ms
  assert(svc.nextWaitTimeoutMs(fakeNowNs) == 16);

  // Stop repeat timer -> back to idle -1
  svc.stopTimer(idRepeat);
  assert(!svc.isTimerActive(idRepeat));
  assert(svc.nextWaitTimeoutMs(fakeNowNs) == -1);
}

// Verifies re-entrant stop/start and owner cleanup in TimerService.
unittest {
  import yguilib.controller : Controller, HandleResult;
  import yguilib.events : AppEvent;
  import yguilib.widget : Widget;
  import yguilib.widget.system : WidgetSystem;

  final class DummyCtrl : Controller {
    override HandleResult handleEvent(AppEvent ev) {
      return HandleResult(HandleResult.Result.nothing);
    }
    override bool updateView() { return false; }
    override bool update() { return false; }
    override bool onTimer(TimerId id, float dt) { return false; }
    override void onPush() {}
    override void onPop() {}
    override void onSuspendByModal() {}
    override void onResumeByModal() {}
    @property override bool isModal() const { return false; }
    override void setModal(bool value) {}
    override void sendAppEvent(AppEvent ev) {}
    override void onWidgetReleased(Widget w) {}
  }
  final class DummySys : WidgetSystem {
  }

  long fakeNowNs = 100_000_000L;
  TimerService svc;
  svc.setClock(() => fakeNowNs);

  auto ctrl = new DummyCtrl();
  auto sys = new DummySys();
  auto selfStopOwner = new Object();
  auto cId = svc.startTimer(
    ctrl,
    TimerIntervalMs.fps60,
    TimerMode.repeat
  );
  auto sId = svc.startTimer(sys, 33, TimerMode.repeat);

  // Shorter timer added later clamps wait timeout immediately
  TimerId selfStopId = svc.startTimer(selfStopOwner, 5, TimerMode.repeat);
  assert(svc.nextWaitTimeoutMs(fakeNowNs) == 5);

  fakeNowNs += 5_000_000L;
  svc.fireDueTimers(fakeNowNs, (TimerEntry e, float dt) {
    if (e.owner is selfStopOwner) {
      svc.stopTimer(e.id);
    }
  });
  assert(!svc.isTimerActive(selfStopId));
  assert(svc.nextWaitTimeoutMs(fakeNowNs) == 11);

  svc.stopTimersForOwner(ctrl);
  assert(!svc.isTimerActive(cId));
  assert(svc.isTimerActive(sId));

  svc.stopTimersForOwner(sys);
  assert(!svc.isTimerActive(sId));
  assert(svc.activeCount() == 0);
}

// Verifies >32 simultaneous due timers trigger the SmallBuffer heap-spill path.
unittest {
  enum size_t timerCount = 40;
  long fakeNowNs = 1_000_000_000L;
  TimerService svc;
  svc.setClock(() => fakeNowNs);

  auto owner = new Object();
  TimerId[timerCount] ids;
  size_t firedCount = 0;
  foreach (i; 0 .. timerCount) {
    ids[i] = svc.startTimer(owner, 10, TimerMode.oneShot);
  }
  assert(svc.activeCount() == timerCount);

  fakeNowNs += 10_000_000L;
  TimerId[] firedOrder;
  svc.fireDueTimers(fakeNowNs, (TimerEntry e, float dt) {
    firedOrder ~= e.id;
    if (e.owner is owner) {
      firedCount++;
    }
  });

  assert(firedCount == timerCount);
  assert(firedOrder == ids[]);
  assert(svc.activeCount() == 0);
  assert(svc.nextWaitTimeoutMs(fakeNowNs) == -1);
}
