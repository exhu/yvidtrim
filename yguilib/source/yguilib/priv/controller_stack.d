module yguilib.priv.controller_stack;

import yguilib.controller;

struct ControllerStack {
  void push(Controller c) {
    assert(c !is null);
    c.isModal = false;
    stack ~= c;
    c.onPush();
  }

  void pushModal(Controller c) {
    assert(c !is null);
    c.isModal = true;
    auto active = getActiveOrNull();
    if (active !is null) {
      active.onSuspendByModal();
    }
    stack ~= c;
    c.onPush();
  }

  void pop() {
    auto active = getActiveOrNull();
    if (active is null) {
      return;
    }
    const bool wasModal = active.isModal;
    stack.length -= 1;
    active.onPop();
    active = getActiveOrNull();
    if (active !is null && wasModal) {
      active.onResumeByModal();
    }
  }

  Controller getActiveOrNull() {
    if (stack.length != 0) {
      return stack[$ - 1];
    }
    return null;
  }

  bool empty() const {
    return stack.length == 0;
  }

  size_t length() const {
    return stack.length;
  }

  inout(Controller[]) getAll() inout {
    return stack;
  }

  inout(Controller) opIndex(size_t i) inout {
    assert(i < stack.length);
    return stack[i];
  }

private:
  Controller[] stack;
}

// Verifies ControllerStack push, modal push, and pop lifecycle transitions.
unittest {
  class ModalTrackController : DefaultController {
    string[]* log;
    string name;

    this(string name, string[]* log) {
      super(null);
      this.name = name;
      this.log = log;
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
  }

  string[] log;
  ControllerStack stack;
  assert(stack.empty());
  assert(stack.length == 0);

  auto c1 = new ModalTrackController("c1", &log);
  auto c2 = new ModalTrackController("c2", &log);

  stack.push(c1);
  assert(stack.getActiveOrNull() is c1);
  assert(stack.length == 1);

  stack.pushModal(c2);
  assert(stack.getActiveOrNull() is c2);
  assert(stack.length == 2);

  stack.pop();
  assert(stack.getActiveOrNull() is c1);
  assert(stack.length == 1);

  stack.pop();
  assert(stack.empty());
  assert(stack.getActiveOrNull() is null);

  assert(log == [
    "c1:onPush",
    "c1:onSuspend",
    "c2:onPush",
    "c2:onPop",
    "c1:onResume",
    "c1:onPop"
  ]);
}
