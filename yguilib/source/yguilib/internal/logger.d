module yguilib.internal.logger;

package(yguilib):

import std.logger;
import yguilib.clibs.sdl3;
// SDL_LOGGING=app=trace
class SdlLogger : Logger {
  this(LogLevel lv) @safe {
    super(lv);
  }

  override void writeLogMsg(ref LogEntry payload) @trusted {
    const yguilib_sdl3_LogPriority prio = sdlPriorityFromLogLevel(
      payload.logLevel
    );
    import std.format : format;
    const string logMsg = format(
      "%s [%s] %s\0", payload.timestamp, payload.funcName, payload.msg
    );
    yguilib_sdl3_log_priority(prio, logMsg.ptr);
  }
}

yguilib_sdl3_LogPriority sdlPriorityFromLogLevel(
  LogLevel lv
) @safe pure nothrow {
  switch (lv) {
    case LogLevel.trace:
      return yguilib_sdl3_LogPriority.verbose;
    case LogLevel.info:
      return yguilib_sdl3_LogPriority.info;
    case LogLevel.warning:
      return yguilib_sdl3_LogPriority.warn;
    case LogLevel.error:
      return yguilib_sdl3_LogPriority.error;
    case LogLevel.critical:
    case LogLevel.fatal:
      return yguilib_sdl3_LogPriority.critical;
    default:
      return yguilib_sdl3_LogPriority.debug_;
  }
}

void setupSdlLogger(LogLevel lv) {
  sharedLog = cast(shared) new SdlLogger(lv);
}

unittest {
  auto prevLog = sharedLog;
  scope (exit) sharedLog = prevLog;

  setupSdlLogger(LogLevel.trace);
  info("Testing std.logger integration with SDL_Log (info)");
  warning("Testing std.logger integration with SDL_Log (warning)");
  error("Testing std.logger integration with SDL_Log (error)");

  assert(
    sdlPriorityFromLogLevel(LogLevel.all) ==
      yguilib_sdl3_LogPriority.debug_
  );
  assert(
    sdlPriorityFromLogLevel(LogLevel.trace) ==
      yguilib_sdl3_LogPriority.verbose
  );
  assert(
    sdlPriorityFromLogLevel(LogLevel.info) ==
      yguilib_sdl3_LogPriority.info
  );
  assert(
    sdlPriorityFromLogLevel(LogLevel.warning) ==
      yguilib_sdl3_LogPriority.warn
  );
  assert(
    sdlPriorityFromLogLevel(LogLevel.error) ==
      yguilib_sdl3_LogPriority.error
  );
  assert(
    sdlPriorityFromLogLevel(LogLevel.critical) ==
      yguilib_sdl3_LogPriority.critical
  );
  assert(
    sdlPriorityFromLogLevel(LogLevel.fatal) ==
      yguilib_sdl3_LogPriority.critical
  );
}
