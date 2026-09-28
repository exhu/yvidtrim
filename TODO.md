-=-=-
### Recommended Skills

  #### 1. scaffold-guidemo-page (High Value)

  A skill with a helper script in D (rdmd .agents/skills/scaffold-guidemo-page/scripts/scaffold_page.d) that:

  • Auto-calculates Card Grids: Generates pre-calculated 2x2, 2x1, or 3x1 card bounds for the 1280x720 viewport (e.g. Card 1 at (20, 68,
  605, 280), Card 2 at (645, 68, 615, 280)).
  • Generates Boilerplate: Generates the card hierarchy with standard backgrounds, borders, title labels, and an interactive testbed
  widget.
  • Wired Stubs: Outputs the model fields, controller event handlers, and HUD status format string ready to drop in.

  #### 2. check-guidemo-shortcuts (Quality & Collision Guard)

  A lightweight D validator script (rdmd .agents/skills/check-guidemo-shortcuts/scripts/check_shortcuts.d) that:

  • Scans guidemoapp.d.
  • Reports an overview table of registered keys per page (Page 1 vs Page 2).
  • Flags unhandled keys, duplicate/conflicting keys on the same page, or keys missing from docstrings/HUD status.
  ──────
  ### Recommended Architectural Step: Modularize guidemo

  Before or alongside building a scaffolding skill, splitting guidemo into modular pages is recommended:

    source/guidemo/
      ├── guidemoapp.d              # App entry point, Window, main layout shell, header, footer
      ├── model.d                   # DemoModel and state
      ├── controller.d              # DemoController and event routing
      └── pages/
          ├── layout_painter_page.d # Painter styles, sizing, anchors, flexbox
          ├── textlabel_page.d      # TextLabel alignment, ellipsis, multiline, playground
          └── timeline_page.d       # Future video trim / scrubber showcase

  This would make each showcase self-contained and allow scaffolding skills to generate isolated page modules cleanly without large
  diffs in a single monolithic file.


-=-=



- fix multiline text label and alignment in guidemo, seems layout Size does not account for ellipsis etc.
- move text handling functions and structs from drawing_components.d
- do not recalculate text if dirty = false, check layout_content_size.d as well
- assets management (transparent mapping to embedded import string and file stream data)
- font management (register font data, name, style)
- define modal controller rules (some controllers must still handle events, when modal is active)
- add modal dialog displayed by model on key (and closed by click)
- button
- focus
- modal dialog
- text input
- implement simple ui: control hierarchy system with input: window, widget, label, view, controller, models
