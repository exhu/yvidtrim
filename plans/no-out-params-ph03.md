# Phase 3: `guidemo`

Replace the remaining `out` parameters in `source/guidemo/pages/virtlist_page.d`.

## Files & Changes

### 1. `source/guidemo/pages/virtlist_page.d`
- Add private `struct ItemDimensions`:
  ```d
  private struct ItemDimensions {
    float width;
    float height;
  }
  ```
  (Use file-level `private:` section per `codestyle.md`, not inline `private`.)
- Change `static void computeItemDimensions(in VerticalItemData item, out float wPx, out float hPx)`
  to `static ItemDimensions computeItemDimensions(in VerticalItemData item)`
  and update its call site around line 754.
- Change `static void computeCardDimensions(in HorizontalItemData item, out float wPx, out float hPx)`
  to `static ItemDimensions computeCardDimensions(in HorizontalItemData item)`
  and update its call site around line 1383.

## Rules & Verification
- Follow `codestyle.md` (2-space indent, <= 80 chars/line, opening `{` on same
  line, section visibility labels, no default parameters).
- Run:
  ```bash
  ninja -C _build && meson test -C _build
  rdmd .agents/skills/check-line-length/scripts/check_line_length.d
  rdmd .agents/skills/check-codestyle/scripts/check_style.d
  ```
