module yguilib.timers;
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
struct MeasureTime {
  // TODO querry time via std.datetime or core.time

}

/// gets time in constructor and destructor, dumps duration
struct MeasureScopeTime {
  // TODO

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
