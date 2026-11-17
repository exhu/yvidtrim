module yguilib.timers;
import core.time : MonoTime, ticksToNSecs;
import std.algorithm.comparison : clamp;
import std.math.remainder : fmod;


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
    if (paused || duration <= 0 || step <= 0)
      return;
    final switch (mode) {
      case AnimationWrapMode.once:
        elapsed += step;
        if (elapsed >= duration) {
          elapsed = duration;
          paused = true;
        }
        break;
      case AnimationWrapMode.loop:
        elapsed = fmod(elapsed + step, duration);
        break;
      case AnimationWrapMode.loopInclusive:
        // Reset on the update after reaching duration so 1.0 is observable.
        if (elapsed >= duration)
          elapsed = 0;
        elapsed += step;
        if (elapsed > duration)
          elapsed = duration;
        break;
      case AnimationWrapMode.pingPong:
        elapsed = fmod(elapsed + step, 2.0f * duration);
        break;
    }
  }

  /// Resets elapsed time and pauses.
  void stop() {
    paused = true;
    elapsed = 0;
  }

  void start(float newDuration,
      AnimationWrapMode newMode = AnimationWrapMode.loop) {
    duration = newDuration;
    mode = newMode;
    elapsed = 0;
  }

  void setPause(bool aPaused) nothrow @safe {
    paused = aPaused;
  }

  bool isPaused() const nothrow @safe {
    return paused;
  }

  float getDuration() const nothrow @safe {
    return duration;
  }

  void setDuration(float newDuration) nothrow @safe {
    duration = newDuration;
    if (duration <= 0) {
      elapsed = 0;
    } else if (elapsed > duration) {
      elapsed = duration;
    }
  }

  /// Advances toward duration (forward=true) or 0 (forward=false).
  void stepTowards(float step, bool forward) nothrow @safe {
    if (duration <= 0 || step <= 0) {
      return;
    }
    const float target = forward ? duration : 0.0f;
    if (elapsed < target) {
      elapsed += step;
      if (elapsed >= target) {
        elapsed = target;
        paused = true;
      } else {
        paused = false;
      }
    } else if (elapsed > target) {
      elapsed -= step;
      if (elapsed <= target) {
        elapsed = target;
        paused = true;
      } else {
        paused = false;
      }
    } else {
      paused = true;
    }
  }

  bool isAtTarget(bool forward) const nothrow @safe {
    if (duration <= 0) {
      return true;
    }
    return forward ? (elapsed >= duration) : (elapsed <= 0.0f);
  }

  /// returns [0..1]
  float getProgress() const nothrow @safe {
    if (duration <= 0)
      return 0;
    if (mode == AnimationWrapMode.pingPong) {
      float t = elapsed / duration;
      return clamp(t <= 1.0f ? t : 2.0f - t, 0, 1f);
    }
    return clamp(elapsed / duration, 0, 1f);
  }

  /// Linearly maps progress [0..1] into [minVal..maxVal].
  float map(float minVal, float maxVal) const nothrow @safe {
    return minVal + (maxVal - minVal) * getProgress();
  }

private:
  float elapsed = 0;
  float duration = 1;
  AnimationWrapMode mode = AnimationWrapMode.loop;
  bool paused = true;

}


/// reusable tool to measure parts of code
struct StopWatchNs {
  void reset() {
    fElapsed = 0;
    running = false;
  }

  void start() {
    running = true;
    startTime = currentTimeNs();
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
  long elapsed() {
    return fElapsed;
  }

private:
  void updateElapsed() {
    const long current = currentTimeNs();
    fElapsed += current - startTime;
    startTime = current;
  }

  long startTime = 0;
  long fElapsed = 0;
  bool running = false;
}

struct Timer {
  /// duration in seconds
  void start(float duration) {
    assert(duration >= 0);
    durationNs = cast(long)(duration * 1_000_000_000.0);
    startTimeNs = currentTimeNs();
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
    const long now = currentTimeNs();
    if (now - startTimeNs < durationNs)
      return false;
    if (looping)
      startTimeNs = now;
    else
      running = false;
    return true;
  }

private:
  long durationNs = 1_000_000_000;
  long startTimeNs = 0;
  bool looping = false;
  bool running = false;
}

/// Measures elapsed seconds between consecutive steps (e.g. animation frames).
struct DeltaTimer {
  /// Returns seconds elapsed since previous step,
  /// clamped to [minStep, maxStep].
  /// On the first call (or after reset), returns initialStep.
  float step(
    float minStep = 0.001f,
    float maxStep = 0.1f,
    float initialStep = 1.0f / 60.0f
  ) {
    const long now = currentTimeNs();
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
  long lastTimeNs = 0;
  bool hasLastTime = false;
}

/// gets time in constructor and destructor, dumps duration
struct MeasureScopeTime {
  // TODO

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
  timer.setPause(true);
  assert(isClose(timer.getProgress(), 0.0f));
  timer.update(0.5f);
  assert(isClose(timer.getProgress(), 0.0f));
  timer.setPause(false);
  timer.update(0.5f);
  assert(isClose(timer.getProgress(), 0.5f));
  timer.update(0.5f);
  assert(isClose(timer.getProgress(), 1f));
  // loopInclusive wraps on the next update after reaching 1.0.
  timer.update(0.25f);
  assert(isClose(timer.getProgress(), 0.25f));
  timer.update(0.9f);
  assert(isClose(timer.getProgress(), 1f));
  timer.update(0.2f);
  assert(isClose(timer.getProgress(), 0.2f));

  // loop stays in [0, 1) and preserves sub-frame overshoot.
  timer.start(1.0f, AnimationWrapMode.loop);
  timer.setPause(false);
  timer.update(0.5f);
  assert(isClose(timer.getProgress(), 0.5f));
  timer.update(0.75f);
  assert(isClose(timer.getProgress(), 0.25f));

  // once clamps to 1.0 and pauses.
  timer.start(1.0f, AnimationWrapMode.once);
  timer.setPause(false);
  timer.update(0.6f);
  assert(isClose(timer.getProgress(), 0.6f));
  timer.update(0.8f);
  assert(isClose(timer.getProgress(), 1.0f));
  timer.update(0.5f);
  assert(isClose(timer.getProgress(), 1.0f));

  // pingPong bounces 0 -> 1 -> 0.
  timer.start(1.0f, AnimationWrapMode.pingPong);
  timer.setPause(false);
  timer.update(0.5f);
  assert(isClose(timer.getProgress(), 0.5f));
  timer.update(0.5f);
  assert(isClose(timer.getProgress(), 1.0f));
  timer.update(0.5f);
  assert(isClose(timer.getProgress(), 0.5f));
  timer.update(0.5f);
  assert(isClose(timer.getProgress(), 0.0f));
}

unittest {
  import core.thread : Thread;
  import core.time : msecs;

  StopWatchNs sw;
  assert(sw.elapsed() == 0);

  sw.start();
  Thread.sleep(2.msecs);
  sw.update();
  const ulong first = sw.elapsed();
  assert(first > 0);

  sw.stop();
  const ulong stopped = sw.elapsed();
  assert(stopped >= first);

  Thread.sleep(2.msecs);
  sw.update();
  assert(sw.elapsed() == stopped);

  sw.reset();
  assert(sw.elapsed() == 0);
}

unittest {
  import core.thread : Thread;
  import core.time : msecs;

  Timer timer;
  assert(!timer.updateAndTrigger());

  // Not yet elapsed.
  timer.start(1.0f);
  assert(!timer.updateAndTrigger());

  // One-shot triggers once and stops.
  timer.start(0.005f);
  Thread.sleep(10.msecs);
  assert(timer.updateAndTrigger());
  assert(!timer.updateAndTrigger());

  // Stop prevents triggering even after duration passes.
  timer.start(0.005f);
  timer.stop();
  Thread.sleep(10.msecs);
  assert(!timer.updateAndTrigger());

  // Looping triggers repeatedly, resetting start point on each trigger.
  timer.startLoop(0.010f);
  Thread.sleep(15.msecs);
  assert(timer.updateAndTrigger());
  assert(!timer.updateAndTrigger());
  Thread.sleep(15.msecs);
  assert(timer.updateAndTrigger());

  // Switching from startLoop to start resets looping to false.
  timer.start(0.005f);
  Thread.sleep(10.msecs);
  assert(timer.updateAndTrigger());
  Thread.sleep(10.msecs);
  assert(!timer.updateAndTrigger());
}

unittest {
  import std.math.operations : isClose;

  // AnimationTimer stepTowards, isAtTarget, map, isPaused, setDuration.
  AnimationTimer t;
  t.start(1.0f, AnimationWrapMode.once);
  assert(t.isPaused());
  assert(t.isAtTarget(false));
  assert(!t.isAtTarget(true));

  t.stepTowards(0.4f, true);
  assert(!t.isPaused());
  assert(isClose(t.getProgress(), 0.4f));
  assert(isClose(t.map(0.2f, 1.0f), 0.52f));

  // Reverse mid-way back toward 0.
  t.stepTowards(0.2f, false);
  assert(!t.isPaused());
  assert(isClose(t.getProgress(), 0.2f));
  t.stepTowards(0.5f, false);
  assert(t.isPaused());
  assert(t.isAtTarget(false));
  assert(isClose(t.getProgress(), 0.0f));

  // Forward to completion.
  t.setDuration(0.5f);
  assert(isClose(t.getDuration(), 0.5f));
  t.stepTowards(0.5f, true);
  assert(t.isPaused());
  assert(t.isAtTarget(true));
  assert(isClose(t.getProgress(), 1.0f));
}

unittest {
  import core.thread : Thread;
  import core.time : msecs;
  import std.math.operations : isClose;

  DeltaTimer dt;
  const float first = dt.step(0.001f, 0.1f, 0.016f);
  assert(isClose(first, 0.016f));

  Thread.sleep(5.msecs);
  const float second = dt.step(0.001f, 0.1f, 0.016f);
  assert(second >= 0.001f && second <= 0.1f);

  dt.reset();
  const float afterReset = dt.step(0.001f, 0.1f, 0.02f);
  assert(isClose(afterReset, 0.02f));
}
