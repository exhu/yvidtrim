module yguilib.controller.internal.controller_stack;

package(yguilib):

import yguilib.allochelpers : ReusableArray, SmallBuffer;
import yguilib.controller : Controller;

struct ControllerStackStorage {
  void push(Controller c) {
    assert(c !is null, "Controller must not be null");
    assert(!inTransition, "Re-entrant ControllerStackStorage mutation");
    assert(!contains(c), "Controller already on stack");
    inTransition = true;
    scope (exit) inTransition = false;
    stack.push(StackEntry(c, false, null));
    c.onPush();
  }

  /// Inserts `c` at the bottom of the stack (index 0) so existing
  /// controllers remain above it in dispatch order.
  void pushBottom(Controller c) {
    assert(c !is null, "Controller must not be null");
    assert(!inTransition, "Re-entrant ControllerStackStorage mutation");
    assert(!contains(c), "Controller already on stack");
    inTransition = true;
    scope (exit) inTransition = false;
    stack.push(StackEntry(c, false, null));
    for (size_t i = stack.length - 1; i > 0; i--) {
      stack[i] = stack[i - 1];
    }
    stack[0] = StackEntry(c, false, null);
    c.onPush();
  }

  /// Pushes `c` as a modal controller, suspending the current top controller.
  /// Note: modal event-blocking relies on `HandleResult.consume` (full modal
  /// barrier is deferred to TODO.md).
  void pushModal(Controller c) {
    assert(c !is null, "Controller must not be null");
    assert(!inTransition, "Re-entrant ControllerStackStorage mutation");
    assert(!contains(c), "Controller already on stack");
    inTransition = true;
    scope (exit) inTransition = false;
    Controller suspended = activeOrNull();
    stack.push(StackEntry(c, true, suspended));
    if (suspended !is null) {
      suspended.onSuspendByModal();
    }
    c.onPush();
  }

  void pop() {
    assert(!inTransition, "Re-entrant ControllerStackStorage mutation");
    if (stack.empty) {
      return;
    }
    inTransition = true;
    scope (exit) inTransition = false;
    StackEntry entry = stack.back();
    stack.popBack();
    entry.ctrl.onPop();
    if (entry.isModal && entry.suspendedTarget !is null &&
        contains(entry.suspendedTarget)) {
      entry.suspendedTarget.onResumeByModal();
    }
  }

  /// Returns the top controller, or null if the stack is empty.
  Controller activeOrNull() {
    if (!stack.empty) {
      return stack.back().ctrl;
    }
    return null;
  }

  bool empty() const {
    return stack.empty;
  }

  size_t length() const {
    return stack.length;
  }

  bool isModal(in Controller c) const {
    foreach (ref entry; stack[]) {
      if (entry.ctrl is c) {
        return entry.isModal;
      }
    }
    return false;
  }

  /// Copies active controllers (bottom to top) into `dst`.
  void snapshot(ref SmallBuffer!(Controller, 16) dst) {
    dst.clear();
    foreach (ref entry; stack[]) {
      dst.push(entry.ctrl);
    }
  }

  inout(Controller) opIndex(size_t i) inout {
    assert(i < stack.length);
    return stack[i].ctrl;
  }

  int opApply(scope int delegate(Controller) dg) {
    SmallBuffer!(Controller, 16) snap;
    snapshot(snap);
    foreach (c; snap[]) {
      if (int res = dg(c)) {
        return res;
      }
    }
    return 0;
  }

private:
  struct StackEntry {
    Controller ctrl;
    bool isModal;
    Controller suspendedTarget;
  }

  bool contains(in Controller c) const {
    foreach (ref entry; stack[]) {
      if (entry.ctrl is c) {
        return true;
      }
    }
    return false;
  }

  ReusableArray!StackEntry stack;
  bool inTransition = false;
}

// Verifies ControllerStackStorage push, modal push, pop, snapshot, and guards.
unittest {
  import core.exception : AssertError;
  import std.exception : assertThrown;
  import yguilib.events : AppEvent;
  import yguilib.controller : HandleResult;
  import yguilib.timercontrol : TimerId;
  import yguilib.widget : Widget;

  class ModalTrackController : Controller {
    string[]* log;
    string name;
    void delegate() onPushHook;
    void delegate() onPopHook;

    this(string name, string[]* log) {
      assert(log !is null);
      this.name = name;
      this.log = log;
    }

    override HandleResult handleEvent(AppEvent ev) {
      return HandleResult(HandleResult.Result.nothing);
    }

    override bool updateView() {
      return false;
    }

    override bool update() {
      return false;
    }

    override bool onTimer(TimerId id, float dt) {
      return false;
    }

    override void onPush() {
      *log ~= name ~ ":onPush";
      if (onPushHook !is null) {
        onPushHook();
      }
    }

    override void onPop() {
      *log ~= name ~ ":onPop";
      if (onPopHook !is null) {
        onPopHook();
      }
    }

    override void onSuspendByModal() {
      *log ~= name ~ ":onSuspend";
    }

    override void onResumeByModal() {
      *log ~= name ~ ":onResume";
    }

    @property override bool modal() const {
      return false;
    }

    override void sendAppEvent(AppEvent ev) {
    }

    override void onWidgetReleased(Widget w) {
    }
  }

  string[] log;
  ControllerStackStorage stack;
  assert(stack.empty());
  assert(stack.length == 0);

  // Empty pop is a safe no-op.
  stack.pop();
  assert(stack.empty());

  auto c1 = new ModalTrackController("c1", &log);
  auto c2 = new ModalTrackController("c2", &log);
  auto c3 = new ModalTrackController("c3", &log);

  // Non-modal push + pop.
  stack.push(c1);
  assert(stack.activeOrNull() is c1);
  assert(stack.length == 1);
  assert(!stack.isModal(c1));
  stack.pop();
  assert(stack.empty());
  assert(log == ["c1:onPush", "c1:onPop"]);

  // pushModal on empty stack + pop.
  log = null;
  stack.pushModal(c1);
  assert(stack.isModal(c1));
  stack.pop();
  assert(stack.empty());
  assert(log == ["c1:onPush", "c1:onPop"]);

  // Nested modals: c1 -> modal c2 -> modal c3.
  log = null;
  stack.push(c1);
  stack.pushModal(c2);
  stack.pushModal(c3);
  assert(stack.length == 3);
  assert(stack[0] is c1);
  assert(stack[1] is c2);
  assert(stack[2] is c3);
  assert(!stack.isModal(c1));
  assert(stack.isModal(c2));
  assert(stack.isModal(c3));

  // opApply order (bottom to top) and early break.
  Controller[] visited;
  foreach (c; stack) {
    visited ~= c;
  }
  assert(visited.length == 3);
  assert(visited[0] is c1 && visited[1] is c2 && visited[2] is c3);

  visited = null;
  foreach (c; stack) {
    visited ~= c;
    if (c is c2) {
      break;
    }
  }
  assert(visited.length == 2);
  assert(visited[0] is c1 && visited[1] is c2);

  // Duplicate push guards.
  assertThrown!AssertError(stack.push(c1));
  assertThrown!AssertError(stack.pushModal(c2));

  stack.pop();
  assert(stack.activeOrNull() is c2);
  stack.pop();
  assert(stack.activeOrNull() is c1);
  stack.pop();
  assert(stack.empty());
  assert(stack.activeOrNull() is null);

  assert(log == [
    "c1:onPush",
    "c1:onSuspend",
    "c2:onPush",
    "c2:onSuspend",
    "c3:onPush",
    "c3:onPop",
    "c2:onResume",
    "c2:onPop",
    "c1:onResume",
    "c1:onPop"
  ]);

  // Re-entrancy guard during onPush / onPop.
  auto reent = new ModalTrackController("reent", &log);
  reent.onPushHook = () {
    stack.push(c1);
  };
  assertThrown!AssertError(stack.push(reent));
  assert(stack.activeOrNull() is reent);
  reent.onPushHook = null;

  reent.onPopHook = () {
    stack.pop();
  };
  assertThrown!AssertError(stack.pop());
  assert(stack.empty());

  // pushBottom inserts below existing controllers.
  stack.push(c1);
  stack.push(c2);
  stack.pushBottom(c3);
  assert(stack.length == 3);
  assert(stack[0] is c3);
  assert(stack[1] is c1);
  assert(stack[2] is c2);
  assert(stack.activeOrNull() is c2);
}
