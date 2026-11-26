module yguilib.controller.internal.controller_stack;

package(yguilib):

import yguilib.allochelpers : ReusableArray;
import yguilib.controller : Controller;

struct ControllerStack {
  void push(Controller c) {
    assert(c !is null);
    c.modal(false);
    stack.push(c);
    c.onPush();
  }

  void pushModal(Controller c) {
    assert(c !is null);
    c.modal(true);
    auto active = activeOrNull();
    if (active !is null) {
      active.onSuspendByModal();
    }
    stack.push(c);
    c.onPush();
  }

  void pop() {
    auto active = activeOrNull();
    if (active is null) {
      return;
    }
    const bool wasModal = active.modal;
    stack.popBack();
    active.onPop();
    active = activeOrNull();
    if (active !is null && wasModal) {
      active.onResumeByModal();
    }
  }

  Controller activeOrNull() {
    if (!stack.empty) {
      return stack.back();
    }
    return null;
  }

  bool empty() const {
    return stack.empty;
  }

  size_t length() const {
    return stack.length;
  }

  inout(Controller[]) controllers() inout {
    return stack[];
  }

  inout(Controller) opIndex(size_t i) inout {
    assert(i < stack.length);
    return stack[i];
  }

  int opApply(scope int delegate(Controller) dg) {
    foreach (c; stack[]) {
      if (int res = dg(c)) {
        return res;
      }
    }
    return 0;
  }

private:
  ReusableArray!Controller stack;
}

// Verifies ControllerStack push, modal push, and pop lifecycle transitions.
unittest {
  import yguilib.events : AppEvent;
  import yguilib.controller : HandleResult;
  import yguilib.timercontrol : TimerId;
  import yguilib.widget : Widget;

  class ModalTrackController : Controller {
    string[]* log;
    string name;
    bool modalFlag = false;

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
    }

    override void onPop() {
      *log ~= name ~ ":onPop";
    }

    override void onSuspendByModal() {
      *log ~= name ~ ":onSuspend";
    }

    override void onResumeByModal() {
      *log ~= name ~ ":onResume";
    }

    @property override bool modal() const {
      return modalFlag;
    }

    @property override void modal(bool value) {
      modalFlag = value;
    }

    override void sendAppEvent(AppEvent ev) {
    }

    override void onWidgetReleased(Widget w) {
    }
  }

  string[] log;
  ControllerStack stack;
  assert(stack.empty());
  assert(stack.length == 0);

  auto c1 = new ModalTrackController("c1", &log);
  auto c2 = new ModalTrackController("c2", &log);

  stack.push(c1);
  assert(stack.activeOrNull() is c1);
  assert(stack.length == 1);

  stack.pushModal(c2);
  assert(stack.activeOrNull() is c2);
  assert(stack.length == 2);

  stack.pop();
  assert(stack.activeOrNull() is c1);
  assert(stack.length == 1);

  stack.pop();
  assert(stack.empty());
  assert(stack.activeOrNull() is null);

  assert(log == [
    "c1:onPush",
    "c1:onSuspend",
    "c2:onPush",
    "c2:onPop",
    "c1:onResume",
    "c1:onPop"
  ]);
}
