# Widget Systems Refactoring Plan: Overview

This document outlines the multi-phase refactoring plan to generalize `yguilib`
widget tree processing into a unified, extensible `WidgetSystem` pipeline,
based on `documentation/systems-review-to-extend.md` and
`documentation/refactoring-prompt.txt`.

Each phase is self-contained, leaves the workspace in a clean, compilable state
passing all unit tests (`ninja -C _build && meson test -C _build`), and adheres
to `codestyle.md` and `AGENTS.md`.

---

## 1. Key Architectural Decisions

1. **Public Visibility Types (`yguilib.widget.visible`)**:
   - Move `VisibleWidget` and `VisibleWidgets` from
     `yguilib.widget.internal.collect_visible` into a dedicated public module
     `yguilib/source/yguilib/widget/visible.d`
     (`module yguilib.widget.visible;`).
   - Keep `VisibleWidgetsCollector` in
     `yguilib/source/yguilib/widget/internal/collect_visible.d` with
     `package(yguilib):` visibility.

2. **New Modules for New Classes**:
   - Create dedicated modules for new abstractions so existing modules do not
     grow excessively:
     - `yguilib/source/yguilib/widget/visible.d`: `VisibleWidget`,
       `VisibleWidgets`.
     - `yguilib/source/yguilib/widget/system.d`: `WidgetSystemHost`,
       `SystemPhase`, `SystemEventResult`, `WidgetSystemContext`,
       `WidgetSystem`, `TwoPassWidgetSystem`.
     - `yguilib/source/yguilib/widget/internal/system_pipeline.d`:
       `WidgetSystemPipeline`.

3. **Read-Only `WidgetSystem.priority` Property & Priority Constants**:
   - `WidgetSystem.priority` is exposed as a read-only `@property int priority()
     const nothrow @safe` (returning `fPriority`, initialized to
     `defaultPriority` or via a `protected this(int priority = defaultPriority)`
     constructor) rather than a mutable public field.
   - Define named priority constants on `WidgetSystem` instead of magic numbers:
     ```d
     enum int focusSystemPriority   = -100;
     enum int inputSystemPriority   = 0;
     enum int layoutSystemPriority  = 0;
     enum int painterSystemPriority = 0;
     enum int defaultPriority       = 0;
     ```

4. **User-Defined Component Storage on `WidgetComponents`**:
   - Preserve direct field access for built-in components while adding a
     type-indexed map `private Component[TypeInfo_Class] custom;` with
     `set!C(C comp)` and `get!C()` methods on `WidgetComponents` (and a fluent
     `.component!C(C comp)` helper on `WidgetBuilder`).

5. **Decoupled Dirty-Flag Lifecycle in `WidgetSystemPipeline`**:
   - `LayoutSystem` and custom `SystemPhase.layout` systems mutate `w.rect`
     without prematurely clearing `w.layoutDirty`. After all `layout` systems
     complete, `WidgetSystemPipeline` compares `w.rect` against pre-layout
     snapshots, sets `w.dirty = true` on geometry changes, and clears
     `w.layoutDirty = false`.
   - `WidgetPainterSystem` and custom `SystemPhase.render` systems draw widgets
     without prematurely clearing `w.dirty`. After all `render` systems
     complete, `WidgetSystemPipeline` clears `w.dirty = false` across rendered
     widgets.

---

## 2. Architecture & Module Dependency Diagram

```text
+--------------------------------------------------------------------------+
|                              Public API                                  |
|                                                                          |
|  yguilib.uisystem                                                        |
|    +-- WidgetSystemControl (register / unregister / findWidgetSystem)    |
|    +-- UiSystem : ControllerStack, WidgetSystemHost, FocusControl,       |
|                   WidgetSystemControl                                    |
|                                                                          |
|  yguilib.widget.visible                                                  |
|    +-- struct VisibleWidget { widget, absRect, hasClip, clipRect }       |
|    +-- alias VisibleWidgets = VisibleWidget[]                            |
|                                                                          |
|  yguilib.widget.system                                                   |
|    +-- interface WidgetSystemHost : EventControl                         |
|    +-- enum SystemPhase { none, event, preLayout, layout,                |
|                           postLayout, render }                           |
|    +-- struct SystemEventResult { consumed, requestUpdateView }          |
|    +-- struct WidgetSystemContext { host, window, root, renderer,        |
|                                     visibleWidgets, unclippedWidgets }   |
|    +-- abstract class WidgetSystem (readonly @property priority,         |
|          priority constants, phases, lifecycle hooks, traversals)        |
|    +-- abstract class TwoPassWidgetSystem : WidgetSystem                 |
|                                                                          |
|  yguilib.widget (package.d)                                              |
|    +-- struct WidgetComponents { ..., set!C(comp), get!C() }             |
+------------------------------------+-------------------------------------+
                                     |
                                     v
+--------------------------------------------------------------------------+
|                         Internal Implementation                          |
|                                                                          |
|  yguilib.internal.uisystem_impl / uisystem_controller                    |
|    +-- Owns WidgetSystemPipeline & registers built-in systems            |
|                                                                          |
|  yguilib.widget.internal.system_pipeline                                 |
|    +-- final class WidgetSystemPipeline                                  |
|          +-- Event phase dispatch                                        |
|          +-- PreLayout -> Unclipped collect -> Layout -> Dirty sync      |
|          +-- Clipped collect -> PostLayout -> Render -> Clear dirty      |
|                                                                          |
|  Built-in Systems (inheriting WidgetSystem):                             |
|    +-- FocusSystem         (priority = focusSystemPriority   [-100])     |
|    +-- InputSystem         (priority = inputSystemPriority   [   0])     |
|    +-- LayoutSystem        (priority = layoutSystemPriority  [   0])     |
|    +-- WidgetPainterSystem (priority = painterSystemPriority [   0])     |
+--------------------------------------------------------------------------+
```

---

## 3. Implementation Sequence & Phase References

Execute the phases in the exact order listed below. After each phase, run build,
test, and code-style verification before proceeding to the next phase.

1. **Phase 1: Public `VisibleWidget` API & Custom `WidgetComponents`**
   - Document: `documentation/systems-refactoring-plan-phase-1.md`
   - Scope: Extract `VisibleWidget` and `VisibleWidgets` to
     `yguilib.widget.visible`, update internal imports, and add `set!C` /
     `get!C` custom component support to `WidgetComponents` and `WidgetBuilder`.

2. **Phase 2: `WidgetSystem` Base Class, Priority Constants & Context**
   - Document: `documentation/systems-refactoring-plan-phase-2.md`
   - Scope: Create `yguilib.widget.system` with `WidgetSystemHost`,
     `SystemPhase`, `SystemEventResult`, `WidgetSystemContext`, `WidgetSystem`
     (with read-only `@property priority` and named priority constants), and
     `TwoPassWidgetSystem`.

3. **Phase 3: Adapt Core Systems to Inherit `WidgetSystem`**
   - Document: `documentation/systems-refactoring-plan-phase-3.md`
   - Scope: Update `FocusSystem`, `InputSystem`, `LayoutSystem`, and
     `WidgetPainterSystem` to inherit `WidgetSystem`, use named priority
     constants, accept `WidgetSystemHost`, and implement phase overrides while
     keeping existing methods operational.

4. **Phase 4: Implement `WidgetSystemPipeline`**
   - Document: `documentation/systems-refactoring-plan-phase-4.md`
   - Scope: Create `yguilib.widget.internal.system_pipeline` to manage
     phase-sorted `WidgetSystem` execution, per-window visibility collection,
     layout rect snapshotting, and post-phase `layoutDirty` / `dirty` flag
     management.

5. **Phase 5: Wire `UiSystem`, `UiSystemImpl` & `UiSystemController`**
   - Document: `documentation/systems-refactoring-plan-phase-5.md`
   - Scope: Add `WidgetSystemControl` to `UiSystem`, implement system
     registration/lookup in `UiSystemImpl`, replace hardcoded system calls in
     `UiSystemController` with `WidgetSystemPipeline`, and add end-to-end
     integration tests.

---

## 4. Verification Checklist (Run After Every Phase)

Every agent executing a phase must run these checks before completing the phase:

```bash
# 1. Build and run all unit tests
ninja -C _build && meson test -C _build

# 2. Check architectural boundaries
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d

# 3. Check code style on modified files
rdmd .agents/skills/check-codestyle/scripts/check_style.d

# 4. Check 80-char line length limit
rdmd .agents/skills/check-line-length/scripts/check_line_length.d

# 5. Check null-safety contracts and invariants
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
```
