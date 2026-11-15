module yguilib.timers;
import std.algorithm.comparison : clamp;
import std.math.algebraic : fabs;


// TODO write unittests
struct TimeCounter {
  void update(float step) {
    accumulatedSteps += step;

  }

  /// returns (-n..+n)
  float progress() {
    return accumulatedSteps / intervalSeconds;
  }

  /// returns [0..1], negative time roundtrips
  float progressClamped() {
    return clamp(fabs(progress()), 0f, 1f);
  }

  /// returns [0..1] but as reminder, negative time roundtrips
  float progressAround() {
    return clamp(fabs(progress() % intervalSeconds), 0f, 1f);
  }

  float intervalSeconds = 1;

private:
  float accumulatedSteps = 0;

}

/// reusable tool to measure parts of code
struct MeasureTime {
  // TODO

}

/// gets time in constructor and destructor, dumps duration
struct MeasureScopeTime {
  // TODO

}
