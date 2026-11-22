# Phase 3: Documentation & Cleanup

## Goal
Update `ARCHITECTURE.md` and `TODO.md`, and perform final full repository
verification.

## Prerequisites
Phases 1 and 2 are complete and passing all tests and audits.

## Files to Modify

### 1. `ARCHITECTURE.md`
- Under `yguilib/source/yguilib/controls/`, add `tooltip.d` in alphabetical
  order:
  `├── tooltip.d               # Tooltip component, overlay layer & system`
- Verify `ARCHITECTURE.md` remains under 250 lines and <= 80 chars/line.

### 2. `TODO.md`
- Remove the completed first item (lines 1-8, the guidemo tooltip popup layer
  widget, system, and component item).

## Verification
```bash
ninja -C _build && meson test -C _build
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit
rdmd .agents/skills/check-boundaries/scripts/check_boundaries.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/check-null-safety/scripts/check_null_safety.d
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
```
