# Replace `out` and Output-Flag `ref` Parameters

Replace all `out` parameters and output-flag `ref` parameters across `yguilib`
and `guidemo` with explicit return values:

- `std.typecons.Nullable!T` for single optional results (matching existing
  `tryPopFront`, `tryPopBack`, and `getAppEvent` conventions).
- Named `struct` types for multi-value results.

Also update `codestyle.md`, add an automated `out`-parameter check to
`.agents/skills/check-codestyle/scripts/check_style.d`, and remove the
completed first item from `TODO.md`.

## Allowed `ref` Uses (Kept Unchanged)

- In-place mutation of existing state, context, cache, or handle
  (`ref WidgetSystemContext`, `ref ModelTracker!M`, `stopTimer(ref TimerId)`).
- Hot-path reusable buffers (`ref SmallBuffer`, `ref ReusableArray`,
  `ref Appender`).
- Fluent struct builders (`ref WidgetBuilder`, `ref HoverButtonBuilder`) and
  large input parameter structs (`in`, `const ref`, or `ref`).

## Phases

- Phase 1: [no-out-params-ph01.md](no-out-params-ph01.md)
  - `yguilib` core (`internal/uisystem_impl.d`) and widget internals
    (`layout_content_size.d`, `layout_flex.d`, `layout_system.d`,
    `input_system.d`, `virtlist_system.d`).
- Phase 2: [no-out-params-ph02.md](no-out-params-ph02.md)
  - `yguilib.controls` (`common.d`, `scrollbars.d`, `tabcontrol.d`,
    `virtlist.d`).
- Phase 3: [no-out-params-ph03.md](no-out-params-ph03.md)
  - `guidemo` (`source/guidemo/pages/virtlist_page.d`).
- Phase 4: [no-out-params-ph04.md](no-out-params-ph04.md)
  - `codestyle.md`, `check_style.d`, `check-codestyle/SKILL.md`, `TODO.md`,
    and full repository verification.
