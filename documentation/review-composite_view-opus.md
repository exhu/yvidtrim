# Review: `yguilib/controls/composite_view.d`

Reviewed at commit `e4f2b16` ("composite_view cleanup after neon 4 review").
Checked against `ModelTracker` (`model.d`), `WidgetViewBase`
(`widget/widget_view.d`) and the callers in `tabcontrol.d`, `virtlist.d` and
`scrollbars.d`. The build and tests were not run for this review.

The module is in good shape: there are no correctness bugs in how it is used
today. There are two real problems that callers could hit later, plus some
smaller points.

## Worth fixing

### 1. `updateCompositeEntries` breaks silently if `Entry` is a struct

Location: `composite_view.d:77`.

`foreach (entry; entries)` works on a copy of each entry. If `Entry` were a
struct, `entry.tracker.update()` and `entry.viewDirty = false` would change
only the copy. `update()` would then report a change on every call.
`findEntry` and `entryField` already require a type that can be null, but
this function has no constraint.

Fix: add `if (is(Entry == class))`, or use `foreach (ref entry; entries)`.
The class constraint makes more sense, since the helpers assume entries are
references. Add the same constraint to `unregisterCompositeWidget` for
consistency.

### 2. `unregisterCompositeWidget` jumps straight to `WidgetViewBase`

Location: `composite_view.d:72`.

The call `view.WidgetViewBase.unregisterViewWidget` is non-virtual, which is
right for avoiding the recursion. But it skips any override between the
caller and `WidgetViewBase`.

Say someone later writes `class FancyTabs : TabControlWidgetView` with its
own entry map and calls this helper. The widget would be removed from
`FancyTabs.entries` and from the base list, but
`TabControlWidgetView.tabEntries` would keep a stale entry:

```
FancyTabs.unregisterViewWidget(w)
  -> unregisterCompositeWidget(this, entries, w)
       entries.remove(w)                        ok
       WidgetViewBase.unregisterViewWidget(w)   ok
  TabControlWidgetView.unregisterViewWidget     SKIPPED
       tabEntries[w] stays                      stale
```

Fix: either say in the doc comment that it is only for views that derive
directly from `WidgetViewBase`, or have callers pass the base cleanup as a
delegate or `super` call.

## Minor

### 3. Changing `entries` while `updateCompositeEntries` iterates

Changing the associative array mid-iteration is undefined. If an
`onModelChanged` callback ever releases a widget, the path
`releaseWidget` -> `onWidgetReleased` -> `unregisterViewWidget` would remove
from `entries` during the loop. Today's callbacks (e.g. `syncTabsCount`) do
not release widgets, so a one-line note in the doc comment is enough.

### 4. `entryField`'s constraint is loose

`hasMember` also accepts methods and properties. On the fallback path,
`typeof(__traits(getMember, Entry.init, field)).init` then gives confusing
errors or odd types. The doc says "field", so the constraint could be
tightened, e.g. `is(typeof(__traits(getMember, Entry.init, field).offsetof))`.
Optional.

### 5. `assignBuilderTracker` has an unstated precondition

If `src` was never initialized, the failure is the bare `assert(m !is null)`
inside `ModelTracker`'s constructor. Add
`assert(src.model !is null, "src must be initialized")` and mention it in the
doc. Also, `ModelTracker.from` resets `lastSeenVersion`, so the first
`update()` always reports a change. That is intended, but a short note would
help.

### 6. Some helpers barely earn their place

`assignBuilderModel` (`tracker = ModelTracker!M(model)`) and
`resolveBuilderRegistry` (`registry ? registry : ui`) are no shorter than the
code they replace, and callers have to import them. They do keep the three
controls consistent, so this is a judgment call. Recommendation: inline
`assignBuilderModel` and keep the others.

### 7. `bindCompositeModel`'s `V` has no constraint

If a `V` has no matching `bindModel`, the error points inside the helper. A
constraint like `if (is(typeof(view.bindModel(viewWidget, tracker))))` would
give clearer errors. Cosmetic.

## Tests

The coverage is good. It checks null and unknown widgets, skipping null and
unrelated views, the `onModelChanged == false` vs. `viewDirty` interaction,
and the recursion guard. Missing:

- `entryField` on a field that cannot be null, e.g. an `int` falling back
  to `0`.
- That `assignBuilderTracker` resets `lastSeenVersion`, so the next
  `update()` is true.
- Calling `bindCompositeModel` again on a widget that is already bound. The
  test's `DummyView.bindModel` always creates a new entry, unlike the real
  views.

## Style

Null handling follows `codestyle.md`: parameters that may be null are
documented, and the rest are asserted. Imports are minimal and the comments
are accurate.

## Suggested next steps

Apply #1, #2 (doc version), #3 and #5, add the missing tests, then verify
with `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`.
