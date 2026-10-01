deprecated module yguilib.widget.property_template;

// mixins break autocompletion, so a candidate for removal
deprecated mixin template MarkDirtyProperty(
  T,
  string name,
  T defaultVal = T.init,
  bool layout = false
) {
  mixin(() {
    import std.format : format;

    enum code = q{
      private %1$s f%2$s = defaultVal;
    public:
      @property %1$s %2$s() const { return f%2$s; }
      @property void %2$s(%1$s v) {
        if (f%2$s == v) return;
        f%2$s = v;
        markDirty(layout);
      }
    };
    return format(code, T.stringof, name);
  }());
}

unittest {
  class MockWidget {
    bool dirtyCalled;
    bool lastLayout;
    int markDirtyCount;

    void markDirty(bool layout = false) {
      dirtyCalled = true;
      lastLayout = layout;
      markDirtyCount++;
    }

    mixin MarkDirtyProperty!(int, "count", 10, false);
    mixin MarkDirtyProperty!(string, "title", "initial", true);
    mixin MarkDirtyProperty!(bool, "enabled");
  }

  auto widget = new MockWidget();
  assert(widget.count == 10);
  assert(widget.title == "initial");
  assert(!widget.enabled);
  assert(!widget.dirtyCalled);
  assert(widget.markDirtyCount == 0);

  // Setting the same value does not call markDirty
  widget.count = 10;
  assert(!widget.dirtyCalled);
  assert(widget.markDirtyCount == 0);

  // Changing value with layout = false calls markDirty(false)
  widget.count = 20;
  assert(widget.count == 20);
  assert(widget.dirtyCalled);
  assert(!widget.lastLayout);
  assert(widget.markDirtyCount == 1);

  // Setting same value again does not trigger markDirty
  widget.dirtyCalled = false;
  widget.count = 20;
  assert(!widget.dirtyCalled);
  assert(widget.markDirtyCount == 1);

  // Changing title with layout = true calls markDirty(true)
  widget.title = "updated";
  assert(widget.title == "updated");
  assert(widget.dirtyCalled);
  assert(widget.lastLayout);
  assert(widget.markDirtyCount == 2);

  // Setting same title does not trigger markDirty
  widget.dirtyCalled = false;
  widget.title = "updated";
  assert(!widget.dirtyCalled);
  assert(widget.markDirtyCount == 2);

  // Changing default-configured property calls markDirty(false)
  widget.enabled = true;
  assert(widget.enabled);
  assert(widget.dirtyCalled);
  assert(!widget.lastLayout);
  assert(widget.markDirtyCount == 3);
}
