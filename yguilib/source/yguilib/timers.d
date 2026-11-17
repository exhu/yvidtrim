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

  void setPause(bool aPaused) {
    paused = aPaused;
  }

  /// returns [0..1]
  float getProgress() const {
    if (duration <= 0)
      return 0;
    if (mode == AnimationWrapMode.pingPong) {
      float t = elapsed / duration;
      return clamp(t <= 1.0f ? t : 2.0f - t, 0, 1f);
    }
    return clamp(elapsed / duration, 0, 1f);
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
