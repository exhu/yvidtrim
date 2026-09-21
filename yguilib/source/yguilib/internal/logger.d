module yguilib.internal.logger;

package(yguilib):

import std.logger;
import yguilib.clibs.sdl3;

class SdlLogger : Logger {
  this(LogLevel lv = LogLevel.info) @safe {
    super(lv);
  }

  override void writeLogMsg(ref LogEntry payload) @trusted {
    yguilib_sdl3_LogPriority prio;
    switch (payload.logLevel) {
      case LogLevel.trace:
        prio = yguilib_sdl3_LogPriority.verbose;
        break;
      case LogLevel.info:
        prio = yguilib_sdl3_LogPriority.info;
        break;
      case LogLevel.warning:
        prio = yguilib_sdl3_LogPriority.warn;
        break;
      case LogLevel.error:
        prio = yguilib_sdl3_LogPriority.error;
        break;
      case LogLevel.critical:
      case LogLevel.fatal:
        prio = yguilib_sdl3_LogPriority.critical;
        break;
      default:
        prio = yguilib_sdl3_LogPriority.debug_;
        break;
    }
    import std.string : toStringz;
    yguilib_sdl3_log_priority(prio, payload.msg.toStringz);
  }
}

void setupSdlLogger(LogLevel lv = LogLevel.info) {
  sharedLog = cast(shared) new SdlLogger(lv);
}

unittest {
  setupSdlLogger(LogLevel.trace);
  info("Testing std.logger integration with SDL_Log (info)");
  warning("Testing std.logger integration with SDL_Log (warning)");
  error("Testing std.logger integration with SDL_Log (error)");
}
