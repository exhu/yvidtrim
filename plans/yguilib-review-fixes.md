# `yguilib` Full Review Remediation

Source: `documentation/yguilib-review-report.md` and its 8 package reports
(commit `7a96feaa25bba66718bc02d342f18c7c42932731`). Line numbers in the
reports refer to that commit and drift as phases land; re-check before editing.

## Architecture & Dependency Order

```
ph01 (clibs) -> ph02 (events) -> ph03 (controller) -> ph04 (core runtime)
                                                        |
                                                        v
                                                      ph05 (core utils + encap)
                                                        |
        +-----------------------------------------------+-------------------+
        v                                                                   v
ph06 (render core) -> ph07 (render font/text) -> ph08 (canvas)    ph09 (widget)
                                                                    |  |  |
                                            ph10 (InputSystem) <----+  |  |
                                            ph11 (layout/text) <-------+  |
                                            ph12 (VirtList) <-------------+
                                                    |
                                            ph13 (controls: buttons/tooltip)
                                                    |
                                            ph14 (controls: composites + docs)
```

## Key Decisions

- **Scope**: Address all 353 findings (42 High, 151 Medium, 160 Low). Defer
  only two features already tracked in `TODO.md`: full `FocusSystem` and modal
  event-dispatch barrier / multi-layer suspension rules.
- **`TimerControl` split (`core` 3.3)**: Split `TimerControl.startTimer` into
  `startControllerTimer(Controller, uint, TimerMode)` and
  `startSystemTimer(WidgetSystem, uint, TimerMode)`. `DefaultController` and
  `WidgetSystem` keep their `protected startTimer(intervalMs, mode)` methods.
- **Public API cleanups** (callers migrated in-phase across `yguilib`,
  `guidemo`, `yvidtrim`, `helloworld`):
  - `makeHeadlessUiSystem()` in `yguilib.uisystem`; `package(yguilib):` on
    `internal/uisystem_impl.d` (`core` 3.1).
  - Remove `AppEvent.releaseData` & `~this()`; read-only `AppEvent.kind`
    (`events` 1.1, 1.3).
  - Encapsulate `DefaultController.fUiSystem` (`invariant`), remove public
    `Controller.modal(bool)` setter (`controller` 1.3, 3.1).
  - Move `ButtonBaseConfig` to `controls/common.d`, encapsulate
    `ButtonBuilderCommon`, `VirtListModel.withCount(size_t)` (`controls`
    3.1, 5.3).
  - Return `bool` from `Renderer.resizeRenderTarget()`, restrict
    `Renderer.drawTexture(GLuint, ...)` to `package(yguilib.render)`,
    encapsulate `GradientStops` (`render` 1.4, 3.2; `canvas` 3.1).
  - Immutable `WidgetSystem.priority`; gate `widget/test_fixture.d` under
    `version (unittest):` + `package(yguilib):` (`widget` 3.1).
- **`TODO.md` (ph14)**: Remove `- review other modules in yguilib`.

## Phases

```
  phase  file                          package / focus            findings
  -----  ----------------------------  -------------------------  --------
  ph01   yguilib-review-fixes-ph01.md  clibs & C wrappers           9 (0H)
  ph02   yguilib-review-fixes-ph02.md  events & MessageBus         21 (2H)
  ph03   yguilib-review-fixes-ph03.md  controller stack & base     11 (2H)
  ph04   yguilib-review-fixes-ph04.md  core runtime & TimerControl ~34 (3H)
  ph05   yguilib-review-fixes-ph05.md  core utils & headless encap ~27 (1H)
  ph06   yguilib-review-fixes-ph06.md  render core & package_test  ~36 (4H)
  ph07   yguilib-review-fixes-ph07.md  render font, atlas & cache  ~24 (1H)
  ph08   yguilib-review-fixes-ph08.md  render/canvas & paths       20 (1H)
  ph09   yguilib-review-fixes-ph09.md  widget core & pipeline      ~41 (4H)
  ph10   yguilib-review-fixes-ph10.md  widget InputSystem          ~13 (3H)
  ph11   yguilib-review-fixes-ph11.md  widget layout & text cache  ~39 (5H)
  ph12   yguilib-review-fixes-ph12.md  widget VirtListSystem       ~21 (5H)
  ph13   yguilib-review-fixes-ph13.md  controls buttons & tooltip  ~33 (8H)
  ph14   yguilib-review-fixes-ph14.md  controls composites & docs  ~24 (3H)
```

## Status

```
  phase  status   notes
  -----  -------  ---------------------------------------------------------
  ph01   pending  clibs bindings & C wrappers
  ph02   pending  events lifecycle & MessageBus
  ph03   pending  controller stack & DefaultController
  ph04   pending  core runtime, Window & TimerControl split
  ph05   pending  core utilities & makeHeadlessUiSystem
  ph06   pending  render core, GL state, targets & package_test
  ph07   pending  render font, GlyphAtlas & TextRunCache
  ph08   pending  render/canvas shadows, paths & zero-GC
  ph09   pending  widget core, pipeline, collector & painter
  ph10   pending  widget InputSystem reliability
  ph11   pending  widget layout, text cache & ScrollSystem
  ph12   pending  widget VirtListSystem & components
  ph13   pending  controls buttons, hover, support & tooltip
  ph14   pending  controls composites, ARCHITECTURE.md & TODO.md
```

## Rules for Every Phase

- Follow `AGENTS.md` and `codestyle.md` (2-space indent, max 80 cols,
  `f`-prefixed private fields, no default params, `const` locals).
- Preserve existing docstrings and comments unrelated to your changes.
- Verify with `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
  after edits. Test module count must not drop.
- GL tests must put `scope(exit) w.endTargets();` *after* `w.destroy()`.
