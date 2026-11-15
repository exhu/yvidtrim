module yguilib.timers;
import std.algorithm.comparison : clamp;
import std.math.algebraic : fabs;
import std.math.remainder : fmod;


/// Time counter primarily for animations. Duration in float type means seconds passed.
/// Wraps around.
struct AnimationLoopTimer {
  /// Append seconds passed.
  void update(float step) {
    if (paused)
      return;
    accumulatedSteps += step;
    // wrap around
    accumulatedSteps = fmod(accumulatedSteps, duration+1);
  }

  /// resets accumulated time.
  void stop() {
    paused = true;
    accumulatedSteps = 0;
  }

  void start(float newDuration) {
    duration = newDuration;
    accumulatedSteps = 0;
  }

  void setPause(bool aPaused) {
    paused = aPaused;
  }

  /// returns [0..1]
  float getProgress() {
    return clamp(accumulatedSteps / duration, 0, 1f);
  }

private:
  float accumulatedSteps = 0;
  float duration = 1;
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
  AnimationLoopTimer timer;
  timer.start(1.0);
  timer.setPause(true);
  assert(isClose(timer.getProgress(), 0.0f));
  timer.update(0.5f);
  assert(isClose(timer.getProgress(), 0.0f));
  timer.setPause(false);
  timer.update(0.5f);
  assert(isClose(timer.getProgress(), 0.5f));
  timer.update(0.5f);
  assert(isClose(timer.getProgress(), 1f));
}
