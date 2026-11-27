# ph05: `core` Data Utilities & `UiSystemImpl` Encapsulation

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-core.md` (commit `7a96feaa`).
Paths below are relative to `yguilib/source/yguilib/` unless noted.

Goal: Address remaining `core` findings (`1.5`-`1.9`, `1.12`, `1.16`-`1.17`,
`2.4`-`2.6`, `3.1`, `3.4`, `3.9`-`3.10`, `4.1`, `5.1`, `5.3`, `5.5`, `6.4`).

## Files

- `uisystem.d`, `internal/uisystem_impl.d`
- ~23 external files importing `yguilib.internal.uisystem_impl` across
  `source/guidemo/`, `source/yvidtrim/`, and `yguilib/examples/helloworld/`
- `allochelpers.d`, `model.d`, `object_registry.d`, `serhelpers.d`,
  `texthelpers.d`, `assets.d`

## Steps

1. **Encapsulate `internal/uisystem_impl.d` (`3.1`)**:
   - Add public `UiSystem makeHeadlessUiSystem()` in `uisystem.d` (calling
     `package(yguilib)` factory or `new UiSystemImpl(null)`).
   - Find all external callers via
     `rdmd .agents/skills/search-code/scripts/search_code.d -e 'uisystem_impl' source/ yguilib/examples/`
     and migrate every one to `makeHeadlessUiSystem()` from `yguilib.uisystem`.
   - Add `package(yguilib):` at the top of `internal/uisystem_impl.d`.
2. **`allochelpers.d` (`1.6`, `1.16`, `1.17`, `3.9`, `4.1`)**:
   - In `RingBuffer`, only call `clearSlot` after `move` when
     `hasIndirections!T && !hasElaborateDestructor!T`, and add `~this() {
     clear(); }`.
   - Extend `ReusableArray.compact` null-check with `isFunctionPointer!Pred ||
     is(Pred == interface)`.
   - Compare `cast(size_t)` addresses in `slicesOverlap`.
   - Accept `const(T)[]` in `SmallBuffer.assignSlice` when copyable.
   - Extract shared `growCapacity` helper.
3. **`model.d` (`1.5`, `3.4`, `5.1`, `6.4`)**:
   - Add `@disable this();` and `invariant { assert(m !is null); }` to
     `ModelTracker`.
   - Move `lastSeenVersion` and `m` to `private:` (expose `const` getter if
     needed); rename `version_` -> `fModelVersion`; add `const` to `@property
     const(T) model() const`.
   - Add tests for `from`/`edit`/`commit`.
4. **`object_registry.d` (`1.12`, `2.4`, `5.5`, `6.4`)**:
   - Add `assert(obj !is null)` in `register`.
   - Eliminate redundant AA lookups using `in`.
   - Fix `_id` in unittest; test 2-arg `opApply` and early `break`.
5. **`serhelpers.d` (`1.7`-`1.9`, `2.5`, `5.3`, `6.4`)**:
   - Branch `isUnsigned!T` -> `JSONValue(cast(ulong) value)` in `toJsonValue`.
   - Strip from first `'!'` before `lastIndexOf('.')` in `shortTypeName`.
   - Walk `BaseClassesTuple!T` and use dynamic `shortTypeName(value)` in
     `serializeStructOrClass`.
   - Pre-allocate `new JSONValue[value.length]` for arrays.
   - Prune unused imports (`isFinite`, `isBasicType`, `isSomeChar`) and
     split `toJsonValue` <= 50 lines.
   - Add unit tests for `ulong > long.max`, arrays, AAs, pointers, and
     `shortTypeName` templates.
6. **`texthelpers.d` & `assets.d` (`3.10`, `2.6`)**:
   - Add `GiB` tier to `formatBytes`.
   - Change `enum string defaultTtfFontData` to `immutable string`.

## Verification

- `rdmd .agents/skills/search-code/scripts/search_code.d --expect-none -e 'uisystem_impl' source/ yguilib/examples/`
- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
