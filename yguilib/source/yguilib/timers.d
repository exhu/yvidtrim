module yguilib.timers;
import core.time : MonoTime, ticksToNSecs;
import std.math : isFinite;
import std.math.remainder : fmod;

/// Controls whether a registered UiSystem timer fires once or repeats.
enum TimerMode {
  oneShot,
  repeat,
}

/// Standard timer intervals in milliseconds.
enum TimerIntervalMs : uint {
  fps60 = 16,
}

/// Controls how AnimationTimer behaves when elapsed reaches duration.
enum AnimationWrapMode {
  once,          /// Clamps at 1.0 and pauses.
  loop,          /// Wraps continuously in [0, 1).
  loopInclusive, /// Reaches 1.0 for one update, then resets to 0.
  pingPong,      /// Bounces between 0.0 and 1.0.
}

/// Time counter primarily for animations. Duration in float means seconds.
struct AnimationTimer {
  /// Append seconds passed.
  void update(float step) {
    if (
      fPaused ||
      !(fDuration > 0) ||
      !isFinite(fDuration) ||
      !(step > 0) ||
      !isFinite(step)
    ) {
      return;
    }
    final switch (mode) {
      case AnimationWrapMode.once:
        elapsed += step;
        if (elapsed >= fDuration) {
          elapsed = fDuration;
          fPaused = true;
        }
        break;
      case AnimationWrapMode.loop:
        elapsed = fmod(elapsed + step, fDuration);
        break;
      case AnimationWrapMode.loopInclusive:
        // Reset on the update after reaching duration so 1.0 is observable.
        if (elapsed >= fDuration)
          elapsed = 0;
        elapsed += step;
        if (elapsed > fDuration)
          elapsed = fDuration;
        break;
      case AnimationWrapMode.pingPong:
        elapsed = fmod(elapsed + step, 2.0f * fDuration);
        break;
    }
  }

  /// Resets elapsed time and pauses.
  void stop() {
    fPaused = true;
    elapsed = 0;
  }

  /// Configures duration and wrap mode, resetting elapsed to 0
  /// (remains paused).
  void start(float newDuration, AnimationWrapMode newMode) {
    fDuration = newDuration;
    mode = newMode;
    elapsed = 0;
  }

  void paused(bool isPaused) nothrow @safe {
    fPaused = isPaused;
  }

  bool paused() const nothrow @safe {
    return fPaused;
  }

  float duration() const nothrow @safe {
    return fDuration;
  }

  void duration(float newDuration) nothrow @safe {
    fDuration = newDuration;
    if (!(fDuration > 0) || !isFinite(fDuration)) {
      elapsed = 0;
    } else {
      const float maxElapsed = mode == AnimationWrapMode.pingPong
        ? 2.0f * fDuration
        : fDuration;
      if (elapsed > maxElapsed) {
        elapsed = maxElapsed;
      }
    }
  }

  /// Advances toward duration (forward=true) or 0 (forward=false).
  void stepTowards(float step, bool forward) nothrow @safe {
    if (
      !(fDuration > 0) ||
      !isFinite(fDuration) ||
      !(step > 0) ||
      !isFinite(step)
    ) {
      return;
    }
    const float target = forward ? fDuration : 0.0f;
    if (elapsed < target) {
      elapsed += step;
      if (elapsed >= target) {
        elapsed = target;
        fPaused = true;
      } else {
        fPaused = false;
      }
    } else if (elapsed > target) {
      elapsed -= step;
      if (elapsed <= target) {
        elapsed = target;
        fPaused = true;
      } else {
        fPaused = false;
      }
    } else {
      fPaused = true;
    }
  }

  bool isAtTarget(bool forward) const nothrow @safe {
    if (!(fDuration > 0) || !isFinite(fDuration)) {
      return true;
    }
    return forward ? (elapsed >= fDuration) : (elapsed <= 0.0f);
  }

  /// returns [0..1]
  float progress() const nothrow @safe {
    import std.algorithm.comparison : clamp;
    if (!(fDuration > 0) || !isFinite(fDuration)) {
      return 0;
    }
    if (mode == AnimationWrapMode.pingPong) {
      float t = elapsed / fDuration;
      return clamp(t <= 1.0f ? t : 2.0f - t, 0, 1f);
    }
    return clamp(elapsed / fDuration, 0, 1f);
  }

  /// Linearly maps progress [0..1] into [minVal..maxVal].
  float map(float minVal, float maxVal) const nothrow @safe {
    return minVal + (maxVal - minVal) * progress();
  }

private:
  float elapsed = 0;
  float fDuration = 1;
  AnimationWrapMode mode = AnimationWrapMode.loop;
  bool fPaused = true;

}


/// reusable tool to measure parts of code
struct StopWatchNs {
  /// Sets a custom nanosecond clock delegate, or `null` to use `MonoTime`.
  void clock(long delegate() clockFn) nothrow @safe {
    fClock = clockFn;
  }

  void reset() {
    fElapsed = 0;
    running = false;
  }

  void start() {
    if (running) {
      return;
    }
    running = true;
    startTime = nowNs();
  }

  void update() {
    if (running)
      updateElapsed();
  }

  void stop() {
    if (running) {
      running = false;
      updateElapsed();
    }
  }

  /// time passed in nanoseconds
  long elapsed() const nothrow @safe {
    return fElapsed;
  }

private:
  long nowNs() const {
    return fClock !is null ? fClock() : currentTimeNs();
  }

  void updateElapsed() {
    const long current = nowNs();
    fElapsed += current - startTime;
    startTime = current;
  }

  long delegate() fClock = null;
  long startTime = 0;
  long fElapsed = 0;
  bool running = false;
}

struct Timer {
  /// Sets a custom nanosecond clock delegate, or `null` to use `MonoTime`.
  void clock(long delegate() clockFn) nothrow @safe {
    fClock = clockFn;
  }

  /// duration in seconds
  void start(float duration) {
    assert(isFinite(duration) && duration >= 0);
    durationNs = cast(long)(duration * 1_000_000_000.0);
    startTimeNs = nowNs();
    looping = false;
    running = true;
  }

  void startLoop(float duration) {
    start(duration);
    looping = true;
  }

  void stop() {
    running = false;
  }

  /// returns true if duration has passed.
  /// If duration passed:
  /// stops for one-shot timer, next calls
  /// will return false;
  /// continues for looping but now new
  /// time start point is set, so it won't
  /// consecutively return true if duration
  /// between calls is not reached.
  bool updateAndTrigger() {
    if (!running)
      return false;
    const long now = nowNs();
    if (now - startTimeNs < durationNs)
      return false;
    if (looping)
      startTimeNs = now;
    else
      running = false;
    return true;
  }

private:
  long nowNs() const {
    return fClock !is null ? fClock() : currentTimeNs();
  }

  long delegate() fClock = null;
  long durationNs = 1_000_000_000;
  long startTimeNs = 0;
  bool looping = false;
  bool running = false;
}

/// Measures elapsed seconds between consecutive steps (e.g. animation frames).
struct DeltaTimer {
  /// Sets a custom nanosecond clock delegate, or `null` to use `MonoTime`.
  void clock(long delegate() clockFn) nothrow @safe {
    fClock = clockFn;
  }

  /// Returns seconds elapsed since previous step,
  /// clamped to [minStep, maxStep].
  /// On the first call (or after reset), returns initialStep.
  float step(float minStep, float maxStep, float initialStep) {
    import std.algorithm.comparison : clamp;
    const long now = nowNs();
    if (!hasLastTime) {
      lastTimeNs = now;
      hasLastTime = true;
      return initialStep;
    }
    const long diffNs = now - lastTimeNs;
    lastTimeNs = now;
    const float dt = cast(float) diffNs / 1_000_000_000.0f;
    return clamp(dt, minStep, maxStep);
  }

  void reset() nothrow @safe {
    hasLastTime = false;
  }

private:
  long nowNs() const {
    return fClock !is null ? fClock() : currentTimeNs();
  }

  long delegate() fClock = null;
  long lastTimeNs = 0;
  bool hasLastTime = false;
}

private:
long currentTimeNs() {
  return ticksToNSecs(MonoTime.currTime.ticks);
}

unittest {
  import std.math.operations : isClose;
  // Starts paused with zero progress; updates while paused are ignored.
  AnimationTimer timer;
  timer.start(1.0f, AnimationWrapMode.loopInclusive);
  timer.paused(true);
  assert(isClose(timer.progress(), 0.0f));
  timer.update(0.5f);
  assert(isClose(timer.progress(), 0.0f));
  timer.paused(false);
  timer.update(0.5f);
  assert(isClose(timer.progress(), 0.5f));
  timer.update(0.5f);
  assert(isClose(timer.progress(), 1f));
  // loopInclusive wraps on the next update after reaching 1.0.
  timer.update(0.25f);
  assert(isClose(timer.progress(), 0.25f));
  timer.update(0.9f);
  assert(isClose(timer.progress(), 1f));
  timer.update(0.2f);
  assert(isClose(timer.progress(), 0.2f));

  // loop stays in [0, 1) and preserves sub-frame overshoot.
  timer.start(1.0f, AnimationWrapMode.loop);
  timer.paused(false);
  timer.update(0.5f);
  assert(isClose(timer.progress(), 0.5f));
  timer.update(0.75f);
  assert(isClose(timer.progress(), 0.25f));

  // once clamps to 1.0 and pauses.
  timer.start(1.0f, AnimationWrapMode.once);
  timer.paused(false);
  timer.update(0.6f);
  assert(isClose(timer.progress(), 0.6f));
  timer.update(0.8f);
  assert(isClose(timer.progress(), 1.0f));
  timer.update(0.5f);
  assert(isClose(timer.progress(), 1.0f));

  // pingPong bounces 0 -> 1 -> 0.
  timer.start(1.0f, AnimationWrapMode.pingPong);
  timer.paused(false);
  timer.update(0.5f);
  assert(isClose(timer.progress(), 0.5f));
  timer.update(0.5f);
  assert(isClose(timer.progress(), 1.0f));
  timer.update(0.5f);
  assert(isClose(timer.progress(), 0.5f));
  timer.update(0.5f);
  assert(isClose(timer.progress(), 0.0f));
}

unittest {
  long fakeNow = 1_000_000;
  StopWatchNs sw;
  sw.clock(() => fakeNow);
  assert(sw.elapsed() == 0);

  sw.start();
  fakeNow += 2_000_000;
  sw.start(); // idempotent while running; must not discard elapsed time
  fakeNow += 3_000_000;
  sw.update();
  const long first = sw.elapsed();
  assert(first == 5_000_000);

  fakeNow += 1_000_000;
  sw.stop();
  const long stopped = sw.elapsed();
  assert(stopped == 6_000_000);

  fakeNow += 2_000_000;
  sw.update();
  assert(sw.elapsed() == stopped);

  sw.reset();
  assert(sw.elapsed() == 0);
}

unittest {
  long fakeNow = 0;
  Timer timer;
  timer.clock(() => fakeNow);
  assert(!timer.updateAndTrigger());

  // Not yet elapsed.
  timer.start(1.0f);
  fakeNow += 500_000_000;
  assert(!timer.updateAndTrigger());

  // One-shot triggers once and stops.
  timer.start(0.005f);
  fakeNow += 10_000_000;
  assert(timer.updateAndTrigger());
  assert(!timer.updateAndTrigger());

  // Stop prevents triggering even after duration passes.
  timer.start(0.005f);
  timer.stop();
  fakeNow += 10_000_000;
  assert(!timer.updateAndTrigger());

  // Looping triggers repeatedly, resetting start point on each trigger.
  timer.startLoop(0.010f);
  fakeNow += 15_000_000;
  assert(timer.updateAndTrigger());
  assert(!timer.updateAndTrigger());
  fakeNow += 15_000_000;
  assert(timer.updateAndTrigger());

  // Switching from startLoop to start resets looping to false.
  timer.start(0.005f);
  fakeNow += 10_000_000;
  assert(timer.updateAndTrigger());
  fakeNow += 10_000_000;
  assert(!timer.updateAndTrigger());
}

unittest {
  import std.math.operations : isClose;

  // AnimationTimer stepTowards, isAtTarget, map, paused, duration, stop, NaN.
  AnimationTimer t;
  t.start(1.0f, AnimationWrapMode.once);
  assert(t.paused());
  assert(t.isAtTarget(false));
  assert(!t.isAtTarget(true));

  t.stepTowards(0.4f, true);
  assert(!t.paused());
  assert(isClose(t.progress(), 0.4f));
  assert(isClose(t.map(0.2f, 1.0f), 0.52f));

  // NaN step is ignored cleanly.
  t.stepTowards(float.nan, true);
  t.update(float.nan);
  assert(isClose(t.progress(), 0.4f));

  // Reverse mid-way back toward 0.
  t.stepTowards(0.2f, false);
  assert(!t.paused());
  assert(isClose(t.progress(), 0.2f));
  t.stepTowards(0.5f, false);
  assert(t.paused());
  assert(t.isAtTarget(false));
  assert(isClose(t.progress(), 0.0f));

  // Forward to completion.
  t.duration(0.5f);
  assert(isClose(t.duration(), 0.5f));
  t.stepTowards(0.5f, true);
  assert(t.paused());
  assert(t.isAtTarget(true));
  assert(isClose(t.progress(), 1.0f));

  // stop() resets progress and pauses.
  t.stop();
  assert(t.paused());
  assert(isClose(t.progress(), 0.0f));

  // duration(<= 0) and NaN reset progress to 0.
  t.start(1.0f, AnimationWrapMode.once);
  t.paused(false);
  t.update(0.5f);
  t.duration(0.0f);
  assert(isClose(t.progress(), 0.0f));
  t.duration(float.nan);
  assert(isClose(t.progress(), 0.0f));
  assert(t.isAtTarget(true));

  // pingPong duration() preserves return half up to 2 * duration.
  t.start(1.0f, AnimationWrapMode.pingPong);
  t.paused(false);
  t.update(1.5f); // return half: progress = 0.5
  assert(isClose(t.progress(), 0.5f));
  t.duration(1.0f);
  assert(isClose(t.progress(), 0.5f));
  t.duration(0.6f); // clamps elapsed from 1.5 to 1.2 -> progress = 0.0
  assert(isClose(t.progress(), 0.0f));
}

unittest {
  import std.math.operations : isClose;

  long fakeNow = 10_000_000;
  DeltaTimer dt;
  dt.clock(() => fakeNow);
  const float first = dt.step(0.0f, 0.1f, 0.016f);
  assert(isClose(first, 0.016f));

  // Sub-millisecond immediate step must not be inflated to 1 ms by default.
  fakeNow += 200_000;
  const float immediate = dt.step(0.0f, 0.1f, 1.0f / 60.0f);
  assert(isClose(immediate, 0.0002f));

  fakeNow += 5_000_000;
  const float second = dt.step(0.0f, 0.1f, 0.016f);
  assert(isClose(second, 0.005f));

  dt.reset();
  const float afterReset = dt.step(0.0f, 0.1f, 0.02f);
  assert(isClose(afterReset, 0.02f));
}
