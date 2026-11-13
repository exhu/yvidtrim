# Review: `dumpInfo implementation` (9779091)

2026-11-13. 8 files, +205 / -7.

## Summary

Adds `UiSystem.dumpInfo()`, which returns pretty-printed JSON describing
the controller stack, the registered widget views and view controllers,
and the main window (title, size, root widget name and uId). Supporting
changes:

- `opApply` overloads on `ControllerStack` and `ObjectRegistry`
- a `shortTypeName` helper in `serhelpers`
- a read-only `Window.title` property (field renamed to `fTitle`)
- a stub in the guidemo `TestUiSystem` mock
- the TODO entry is removed

Verification: `ninja -C _build && meson test -C _build` passes (9/9).
No added line is longer than 80 characters.

Verdict: **OK to keep.** It does what the TODO asked. No correctness
bugs found. The items below are small follow-ups.

## Output shape

```
{
  "type": "UiSystem",
  "fields": {
    "controllers": [ { "type": "...", "isModal": false }, ... ],
    "widgetViews": { "<name>": "<ShortType>", ... },
    "widgetViewControllers": { "<name>": "<ShortType>", ... },
    "window": { "title", "width", "height",
                "rootWidget": { "name", "uId" } | null } | null
  }
}
```

This uses the same `{type, fields}` layout as `serializeToJson`, so
tools that read one format can read the other. Key order is stable
because `std.json` sorts object keys when writing output, even though
the source AAs are unordered.

## Findings

### Medium

1. **`UiSystem.dumpInfo()` has no doc comment**
   ([uisystem.d](file://yguilib/source/yguilib/uisystem.d#L49)).
   It reads GUI state without locking. Under the project's threading rule,
   it may only be called on the main thread, but nothing in the code says
   so. Add a `///` comment that covers:
   - the output format (JSON, the `{type, fields}` schema)
   - main-thread only
   - that it is meant for debugging

2. **New iteration APIs have no tests.**
   - `ControllerStack.opApply(size_t, Controller)` has no callers and no
     test.
   - `ControllerStack.opApply(Controller)` is only exercised indirectly,
     through the `dumpInfo` test.
   - `ObjectRegistry.opApply(string, T)` has no direct test. The existing
     registry unittest covers only the value-only overload.

   Either add small unittests next to each type, or drop the unused
   indexed overload.

3. **Two ways to iterate the controller stack.** `ControllerStack`
   already exposes `getAll()`, and `releaseWidget` still uses
   `controllers.getAll()`. Pick one style: switch `releaseWidget` to
   `foreach (ctrl; controllers)`, or use `getAll()` in `dumpInfo` and
   drop the new overloads.

### Low

4. **Test coverage gaps in the `dumpInfo` unittest**
   ([uisystem_impl.d](file://yguilib/source/yguilib/internal/uisystem_impl.d#L1186-L1262)):
   - The `window == null` path is untested. Headless `UiSystemImpl(null)`
     is an officially supported mode, according to the constructor comment.
   - The `rootWidget == null` path is untested.
   - `isModal == true` is never checked. Push one modal controller and
     check stack order and the flag.
   - `controllers.array.length >= 1` could be `== 1`, because the test
     controls the whole stack.

5. **`width`/`height` are logical units, not pixels.** After
   `setUnitsScaling` or a display scale change, `Window.width/height`
   come from the renderer viewport in scaled units. Options:
   - name the keys to say so, or
   - also emit `pixelWidth`/`pixelHeight` and the scaling factors, which
     are useful when debugging HiDPI layout problems.

6. **Only one window is dumped.** The TODO said "windows". Today
   `UiSystemImpl` has only `fMainWindow`, so this is correct. If more
   windows are added later, a `"windows": [...]` array will avoid a schema
   change. Consider emitting an array now.

7. **The mock stub returns `""`**
   ([hover_button.d](file://source/guidemo/hover_button.d#L628-L630)).
   An empty string is not valid JSON. Returning `"{}"` keeps the contract
   valid for any caller that parses the result. More generally, every new
   method on `UiSystem` must be added to each hand-written mock. If this
   keeps happening, consider a shared test base class, such as one in
   `widget/test_fixture.d`.

8. **`shortTypeName` drops template arguments.** I checked this with
   ldc2: `Box!Foo` and `Box!int` both print as `Box`. This is fine for
   debug output. A short note in the doc comment would make the behaviour
   clear.

9. **`serializeToJson(JSONValue(root))` only pretty-prints.** It works,
   because `toJsonValue` passes `JSONValue` through unchanged. Calling
   `toJSON(jv, true, JSONOptions.specialFloatLiterals)` directly would
   say more clearly what the code does. Optional.

10. **Nothing uses it yet.** No debug key binding or guidemo hook calls
    `dumpInfo`. Consider wiring it to a debug key, or logging it at
    startup in guidemo, so it gets used and stays correct.

11. **ARCHITECTURE.md is unchanged.** This is acceptable: no module,
    directory or data-flow changes. A one-line mention under the UiSystem
    section would help people find the feature. Optional.

## Positives

- The `title` getter keeps `Window`'s title read-only. Before this
  change, the field was not visible outside `Window` at all.
- The root widget is dumped shallowly (name and uId only). The test
  asserts that `children` and `components` are absent, which guards
  against accidentally serializing the whole tree.
- `shortTypeName` gets the runtime type for interfaces through
  `cast(Object)`, and handles null. Tests cover both, plus non-class
  values.
- Scoped imports inside `dumpInfo` and `shortTypeName` follow
  `codestyle.md`.
