# Revise D Module Structure

## Goal

Bring the existing D module layout into full compliance with
[codestyle.md](file:///home/yur/agy-projects/yvidtrim/codestyle.md)
section **Architecture & Module Visibility**.  The previous refactor
([refactor-module-structure-plan.md](file:///home/yur/agy-projects/yvidtrim/documentation/refactor-module-structure-plan.md))
established domain directories with `package.d` facades,
`internal/` subdirectories, and `package(yguilib)` access control.
Several rules are still violated.

## Violations Found

### V1 — `package.d` files use re-exports instead of containing
the primary module code

**Rule (codestyle §1):** *"do not use public reexports, first-level
modules inside the package are the public interface."*

When a module is converted into a package (directory with
sub-modules), the original module's code should become `package.d`.
For example, `render.d` → `render/package.d`.  Instead, the
current layout duplicates every module: `render/package.d`
(re-export facade) alongside `render/render.d` (actual code).

Every `package.d` currently uses `public import`:

```
  +-----------------------+--------------------------------------+
  | package.d             | public import used                   |
  +-----------------------+--------------------------------------+
  | app/package.d         | yguilib.app.app : App                |
  | controller/package.d  | yguilib.controller.controller : ...  |
  | events/package.d      | yguilib.events.events : AppEvent     |
  |                       | yguilib.events.keyboard : ...        |
  | model/package.d       | yguilib.model.model : ...            |
  | render/package.d      | yguilib.render.render : Renderer     |
  |                       | yguilib.render.render_types : ...    |
  |                       | yguilib.render.internal.font : Font  |
  | uisystem/package.d    | yguilib.uisystem.uisystem : ...     |
  | widget/package.d      | yguilib.widget.layout : ...          |
  |                       | yguilib.widget.widget : ...          |
  | window/package.d      | yguilib.window.window : Window       |
  +-----------------------+--------------------------------------+
```

**Fix:** For each multi-module package, merge the primary module's
code into `package.d` and delete the redundant file:

| Package        | Merge into `package.d`    | Delete            |
|----------------|---------------------------|-------------------|
| controller/    | controller.d              | controller.d      |
| events/        | events.d                  | events.d          |
| render/        | render.d                  | render.d          |
| widget/        | widget.d                  | widget.d          |

Remove all `public import` lines.  Consumers keep writing
`import yguilib.controller;` — it resolves to `package.d`
which now holds the actual code.

### V2 — Single-module directories with unnecessary `package.d`

**Rule (codestyle §1):** *"do not create a directory for a single
module file as package.d, a single module file is enough in this
case."*

Four directories contain exactly one public module plus its
`package.d`:

```
  +------------+-----------------------+--------------+
  | Directory  | Single public module  | Internal?    |
  +------------+-----------------------+--------------+
  | app/       | app.d                 | none         |
  | model/     | model.d               | none         |
  | uisystem/  | uisystem.d            | none         |
  | window/    | window.d              | none         |
  +------------+-----------------------+--------------+
```

**Fix:** Collapse each — move the `.d` file up one level, delete
the directory and `package.d`.

  Before:  `yguilib/source/yguilib/app/app.d`
           `yguilib/source/yguilib/app/package.d`
  After:   `yguilib/source/yguilib/app.d`

### V3 — `Font` re-exported from `internal/` to public API

**Rule (codestyle §2):** *"Do not mark internal symbols `public`.
Implementation details must never be reachable by external
consumers."*

`render/package.d` contains:
```d
public import yguilib.render.internal.font : Font;
```

This exposes an internal class to external consumers.

**Fix:** Move `Font` out of `internal/` to become a public module:
`yguilib/source/yguilib/render/font.d`.  The `Font` class uses
default (public) visibility for its methods, which is correct for
public API.  Keep only the `package(yguilib)` items
(`defaultFontPtSize`, `handle` field) scoped with
`package(yguilib)`.

### ~~V4~~ — `yguilib.assets` at top level — **Not a violation**

**Rule (codestyle §Resources):** *"Put string imports into
`assets.d` or into `internal/assets.d`."*

`yguilib/source/yguilib/assets.d` contains
`defaultTtfFontData`.  The default font is intended to be public
API available to external consumers, so the top-level `assets.d`
location is correct per the rule.  **No change needed.**

### V5 — `widget/layout.d` missing from `meson.build`

[layout.d](file:///home/yur/agy-projects/yvidtrim/yguilib/source/yguilib/widget/layout.d)
exists on disk but is not listed in
[yguilib/meson.build](file:///home/yur/agy-projects/yvidtrim/yguilib/meson.build).

**Fix:** Add `source/yguilib/widget/layout.d` to `yguilib_src`
in `meson.build`.

### V6 — `widget/component.d` not exported via `widget/package.d`

[component.d](file:///home/yur/agy-projects/yvidtrim/yguilib/source/yguilib/widget/component.d)
is a public module but is not referenced by `widget/package.d`.
Since we are removing re-exports (V1), this is fine — consumers
import `yguilib.widget.component` directly.  No action needed
beyond V1.

### V7 — codestyle.md missing module-to-package conversion rule

The codestyle §1 does not document the rule that when a module is
converted into a package (directory), the original module's code
becomes `package.d`.

**Fix:** Add this rule to
[codestyle.md](file:///home/yur/agy-projects/yvidtrim/codestyle.md)
§1 Structure & Facades.

---

## User Review Required

> [!IMPORTANT]
> **Most consumer imports are unchanged.**  Since primary module
> code merges into `package.d`, `import yguilib.controller;` etc.
> still work.  Only additional sub-modules within a package require
> explicit imports (e.g. `import yguilib.render.render_types;`,
> `import yguilib.render.font;`, `import yguilib.widget.layout;`,
> `import yguilib.events.keyboard;`).

> [!IMPORTANT]
> **`Font` moves from `internal/` to public.**  After V3,
> `yguilib.render.font` becomes a first-level public module.
> Internal modules that import `yguilib.render.internal.font`
> must update their import paths.

## Open Questions

None — all changes follow directly from codestyle.md rules.

---

## Proposed Changes

Ordered by dependency (foundational changes first).

---

### V5 Fix — Add missing `layout.d` to meson.build

#### [MODIFY] [meson.build](file:///home/yur/agy-projects/yvidtrim/yguilib/meson.build)

Add `'source/yguilib/widget/layout.d'` to `yguilib_src`:

```diff
   'source/yguilib/widget/component.d',
   'source/yguilib/widget/internal/widget_painter.d',
+  'source/yguilib/widget/layout.d',
   'source/yguilib/widget/package.d',
   'source/yguilib/widget/widget.d',
```

---

### V3 Fix — Move `Font` from `internal/` to public

#### [NEW] [render/font.d](file:///home/yur/agy-projects/yvidtrim/yguilib/source/yguilib/render/font.d)

Move the entire `Font` class from `render/internal/font.d` here.
Change module declaration to `module yguilib.render.font;`.
Keep `package(yguilib)` on `defaultFontPtSize` and `handle`.

#### [DELETE] [render/internal/font.d](file:///home/yur/agy-projects/yvidtrim/yguilib/source/yguilib/render/internal/font.d)

#### Update all imports (5 files):

| File                          | Old import path                       | New import path                |
|-------------------------------|---------------------------------------|--------------------------------|
| render/render.d               | yguilib.render.internal.font          | yguilib.render.font            |
| render/internal/text_cache.d  | yguilib.render.internal.font          | yguilib.render.font            |
| render/package.d              | yguilib.render.internal.font          | (line removed — V1)            |

#### [MODIFY] [meson.build](file:///home/yur/agy-projects/yvidtrim/yguilib/meson.build)

```diff
-  'source/yguilib/render/internal/font.d',
+  'source/yguilib/render/font.d',
```

---

### V2 Fix — Collapse single-module directories

Four directories → four flat module files.

#### app/ → app.d

##### [DELETE] app/package.d, app/ directory

##### [MODIFY] [app/app.d](file:///home/yur/agy-projects/yvidtrim/yguilib/source/yguilib/app/app.d) → [app.d](file:///home/yur/agy-projects/yvidtrim/yguilib/source/yguilib/app.d)

Move file to parent, change module declaration:

```diff
-module yguilib.app.app;
+module yguilib.app;
```

Update imports referencing `yguilib.app.app` → `yguilib.app`
(only `app/package.d` which is deleted).

Internal import from app.d itself uses `yguilib.uisystem` which
will also be collapsed — handled below.

##### [MODIFY] meson.build

```diff
-  'source/yguilib/app/app.d',
-  'source/yguilib/app/package.d',
+  'source/yguilib/app.d',
```

#### model/ → model.d

##### [DELETE] model/package.d, model/ directory

##### [MODIFY] model/model.d → model.d

```diff
-module yguilib.model.model;
+module yguilib.model;
```

##### [MODIFY] meson.build

```diff
-  'source/yguilib/model/model.d',
-  'source/yguilib/model/package.d',
+  'source/yguilib/model.d',
```

#### uisystem/ → uisystem.d

##### [DELETE] uisystem/package.d, uisystem/ directory

##### [MODIFY] uisystem/uisystem.d → uisystem.d

```diff
-module yguilib.uisystem.uisystem;
+module yguilib.uisystem;
```

##### [MODIFY] meson.build

```diff
-  'source/yguilib/uisystem/package.d',
-  'source/yguilib/uisystem/uisystem.d',
+  'source/yguilib/uisystem.d',
```

#### window/ → window.d

##### [DELETE] window/package.d, window/ directory

##### [MODIFY] window/window.d → window.d

```diff
-module yguilib.window.window;
+module yguilib.window;
```

##### [MODIFY] meson.build

```diff
-  'source/yguilib/window/package.d',
-  'source/yguilib/window/window.d',
+  'source/yguilib/window.d',
```

#### Update internal imports for collapsed modules

These files import the collapsed modules via their old facade path
(`yguilib.app`, `yguilib.model`, etc.) which now resolves to the
flat file directly — **no import path changes needed** for
consumers.  The facade `package.d` previously resolved
`import yguilib.app` to `app/package.d`; now the same import
resolves to `app.d`.

Files using `yguilib.uisystem.uisystem` (fully-qualified internal
path):

| File             | Old import                         | New import              |
|------------------|------------------------------------|-------------------------|
| (none found)     | yguilib.uisystem.uisystem          | yguilib.uisystem        |

The internal import in `app.d` already uses
`import yguilib.uisystem : UiSystem;` (facade path), so it
resolves correctly after collapse.

---

### V1 Fix — Remove public re-exports from remaining `package.d`

After V2, only **4 directories** retain `package.d` (those with
multiple public modules or an `internal/` subdirectory):

```
  controller/package.d    (controller.d + internal/)
  events/package.d        (events.d, keyboard.d + internal/)
  render/package.d        (render.d, render_types.d, font.d
                           + internal/)
  widget/package.d        (widget.d, component.d, layout.d
                           + internal/)
```

For each, merge the primary module's code into `package.d` and
delete the now-redundant file.

#### controller/

##### [MODIFY] [controller/package.d](file:///home/yur/agy-projects/yvidtrim/yguilib/source/yguilib/controller/package.d)

Replace all `public import` lines with the full contents of
`controller/controller.d` (the `Controller` interface,
`HandleResult`, `DefaultController` class).  Change module
declaration to `module yguilib.controller;`.

##### [DELETE] controller/controller.d

##### Update imports referencing `yguilib.controller.controller`:

| File                                  | Old import                            | New import               |
|---------------------------------------|---------------------------------------|--------------------------|
| controller/internal/controller_stack.d | yguilib.controller.controller        | yguilib.controller       |

##### [MODIFY] meson.build

```diff
-  'source/yguilib/controller/controller.d',
   'source/yguilib/controller/internal/controller_stack.d',
   'source/yguilib/controller/package.d',
```

#### events/

##### [MODIFY] [events/package.d](file:///home/yur/agy-projects/yvidtrim/yguilib/source/yguilib/events/package.d)

Replace all `public import` lines with the full contents of
`events/events.d` (the `AppEvent` struct).  Change module
declaration to `module yguilib.events;`.

##### [DELETE] events/events.d

##### Update imports referencing `yguilib.events.events`:

| File                            | Old import                | New import           |
|---------------------------------|---------------------------|----------------------|
| events/keyboard.d               | (no import of events.d)  | (none needed)        |
| events/internal/message_bus.d   | yguilib.events            | (unchanged)          |
| events/internal/sdl_events.d    | yguilib.events            | (unchanged)          |

The internal modules already import `yguilib.events` (the
package), so no changes needed — the package now contains the
code directly.

##### [MODIFY] meson.build

```diff
-  'source/yguilib/events/events.d',
   'source/yguilib/events/internal/message_bus.d',
```

#### render/

##### [MODIFY] [render/package.d](file:///home/yur/agy-projects/yvidtrim/yguilib/source/yguilib/render/package.d)

Replace all `public import` lines with the full contents of
`render/render.d` (the `Renderer` class).  Change module
declaration to `module yguilib.render;`.

##### [DELETE] render/render.d

##### Update imports referencing `yguilib.render.render`:

No internal files import `yguilib.render.render` directly —
they all import `yguilib.render` (the package).  No changes
needed.

##### [MODIFY] meson.build

```diff
   'source/yguilib/render/package.d',
-  'source/yguilib/render/render.d',
   'source/yguilib/render/render_types.d',
```

#### widget/

##### [MODIFY] [widget/package.d](file:///home/yur/agy-projects/yvidtrim/yguilib/source/yguilib/widget/package.d)

Replace all `public import` lines with the full contents of
`widget/widget.d` (the `Widget` class, `Background`, `Border`,
`TextLabel`, etc.).  Change module declaration to
`module yguilib.widget;`.

##### [DELETE] widget/widget.d

##### Update imports referencing `yguilib.widget.widget`:

| File                              | Old import               | New import         |
|-----------------------------------|--------------------------|--------------------|
| widget/internal/widget_painter.d  | yguilib.widget.widget    | yguilib.widget     |

##### [MODIFY] meson.build

```diff
   'source/yguilib/widget/package.d',
-  'source/yguilib/widget/widget.d',
   'source/yguilib/window.d',
```

#### Update consumer imports

Since the primary module code now lives in `package.d`, consumers
that import the package (e.g. `import yguilib.controller;`)
get the same symbols as before — **no changes needed** for most
imports.

**source/yvidtrim/app.d** — the only external consumer:

```diff
 module yvidtrim.app;
 import std.stdio;
 import yguilib.app;
 import yguilib.controller;
 import yguilib.events;
+import yguilib.events.keyboard;
 import yguilib.model;
 import yguilib.render;
+import yguilib.render.font;
+import yguilib.render.render_types;
 import yguilib.uisystem;
 import yguilib.widget;
+import yguilib.widget.layout;
 import yguilib.window;
```

Only the secondary sub-modules (`keyboard`, `font`,
`render_types`, `layout`) need explicit imports since they are
no longer re-exported.

**yguilib internal modules** — import path changes:

| File                              | Old import              | New import                      |
|-----------------------------------|-------------------------|---------------------------------|
| controller/internal/cntrl_stack.d | yguilib.controller      | (unchanged — now resolves to    |
|                                   |                         | package.d with actual code)     |
| widget/internal/widget_painter.d  | yguilib.widget.widget   | yguilib.widget                  |
| widget/layout.d                   | yguilib.widget.component | (unchanged)                    |
| window.d (collapsed)              | yguilib.widget          | (unchanged)                     |

All other internal imports that use the package path
(`yguilib.events`, `yguilib.render`, etc.) resolve correctly
since the code is now in `package.d`.

---

### V7 Fix — Add module-to-package rule to codestyle.md

#### [MODIFY] [codestyle.md](file:///home/yur/agy-projects/yvidtrim/codestyle.md)

Add the following bullet after the "Domain Facades" bullet in
§1 Structure & Facades (after line 49):

```diff
   there are more than one module in the subsystem.
 - do not create a directory for a single module file as
   package.d, a single module file is enough in this case.
+- when converting a module into a package (directory with
+  sub-modules), the original module becomes package.d, e.g.
+  render.d becomes render/package.d containing the original
+  code.
 - do not use public reexports, first-level modules inside
   the package are the public interface.
```

---

### Final meson.build `yguilib_src` listing

After all changes, the full file list in
[yguilib/meson.build](file:///home/yur/agy-projects/yvidtrim/yguilib/meson.build):

```python
yguilib_src = files(
  'source/yguilib/app.d',
  'source/yguilib/assets.d',
  'source/yguilib/clibs/sdl3.d',
  'source/yguilib/clibs/sdl3_ttf.d',
  'source/yguilib/controller/internal/controller_stack.d',
  'source/yguilib/controller/package.d',
  'source/yguilib/events/internal/message_bus.d',
  'source/yguilib/events/internal/sdl_events.d',
  'source/yguilib/events/keyboard.d',
  'source/yguilib/events/package.d',
  'source/yguilib/internal/assets.d',
  'source/yguilib/internal/logger.d',
  'source/yguilib/model.d',
  'source/yguilib/render/font.d',
  'source/yguilib/render/internal/clip_stack.d',
  'source/yguilib/render/internal/gl_util.d',
  'source/yguilib/render/internal/pipelines.d',
  'source/yguilib/render/internal/text_cache.d',
  'source/yguilib/render/package.d',
  'source/yguilib/render/render_types.d',
  'source/yguilib/uisystem.d',
  'source/yguilib/widget/component.d',
  'source/yguilib/widget/internal/widget_painter.d',
  'source/yguilib/widget/layout.d',
  'source/yguilib/widget/package.d',
  'source/yguilib/window.d',
)
```

### Final directory structure

```
yguilib/source/yguilib/
+-- app.d                          (flat, was app/app.d)
+-- assets.d                       (public, unchanged)
+-- model.d                        (flat, was model/model.d)
+-- uisystem.d                     (flat, was uisystem/uisystem.d)
+-- window.d                       (flat, was window/window.d)
+-- clibs/
|   +-- sdl3.d
|   +-- sdl3_ttf.d
+-- controller/
|   +-- package.d                  (primary: Controller, etc.)
|   +-- internal/
|       +-- controller_stack.d
+-- events/
|   +-- package.d                  (primary: AppEvent)
|   +-- keyboard.d
|   +-- internal/
|       +-- message_bus.d
|       +-- sdl_events.d
+-- internal/
|   +-- assets.d
|   +-- logger.d
|   +-- test_main.d
+-- render/
|   +-- package.d                  (primary: Renderer)
|   +-- font.d                     (was internal/font.d)
|   +-- render_types.d
|   +-- internal/
|       +-- clip_stack.d
|       +-- gl_util.d
|       +-- pipelines.d
|       +-- text_cache.d
+-- widget/
    +-- package.d                  (primary: Widget, etc.)
    +-- component.d
    +-- layout.d
    +-- internal/
        +-- widget_painter.d
```

---

## Verification Plan

### Automated Tests

```bash
meson setup _build . --reconfigure
ninja -C _build
meson test -C _build
```

All existing tests must pass (yguilib_test, yvidtrim_sdl3,
yguilib_sdl3, yguilib_sdl3_ttf, glad2gles31d).

### Line Length Check

```bash
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
```

### Manual Verification

Run `./_build/yvidtrim` to verify the application starts, renders
UI elements, handles key events ('q' to quit), and exits cleanly.
