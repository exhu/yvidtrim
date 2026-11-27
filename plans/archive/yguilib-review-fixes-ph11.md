# ph11: `widget` Layout, Text Cache & `ScrollSystem`

Overview: `plans/yguilib-review-fixes.md`.
Review: `documentation/yguilib-review-report-widget.md` (commit `7a96feaa`).
Paths below are relative to `yguilib/source/yguilib/widget/internal/`.

Goal: Address all layout, text wrapping/caching, and `ScrollSystem` findings
(`1.10`-`1.13`, `1.16`, `2.1`, `2.4`, `3.1`-`3.2`, `4.1`-`4.2`, `5.1`-`5.2`,
`6.1`-`6.2`).

## Files

- `layout_content_size.d`, `text_label_cache.d`, `layout_flex.d`,
  `layout_text.d`, `layout_anchor.d`, `layout_axis.d`,
  `layout_dimension.d`, `layout_system.d`, `scroll_system.d`

## Steps

1. **`layout_content_size.d` (`2.1`, `1.16`, `3.2`, `4.1`, `6.1`)**:
   - Call `calcTextContentSize` from `calcContentSize` and remove dead
     `calcConstTextContentSize` (`2.1`).
   - Deduplicate `clampDimension` and `Widget.contentArea()` (`4.1`).
   - Include child margins in `tryCalcChildrenBoundingBox` (`1.16`).
   - Assert `szComp !is null` and document nullable `Renderer` (`3.2`).
   - Add unit tests (`6.1`).
2. **`text_label_cache.d` (`1.12`, `1.13`, `3.2`, `4.1`, `5.1`, `6.1`)**:
   - Extract shared `TextLayoutKey` keyed on `font.id` (`ulong`) and
     `font.scaledSize` (`float`) (`1.12`, `4.1`).
   - Add `bool valid;` to `TextLayoutCache` so empty results (`[]`) cache
     properly (`1.13`).
   - Return `const(FormattedTextLine)[]` and fix null-safety doc/code (`3.2`).
   - Replace 7-10 param functions with `in TextLayoutKey` / param struct
     (`5.1`).
   - Add unit tests (`6.1`).
3. **`layout_flex.d` (`1.10`, `1.16`, `2.4`, `5.2`)**:
   - Add `mainMarginStart(child, isRow) + mainMarginEnd(child, isRow)` to
     `fixedSum` for fraction children and update unittest (`1.10`).
   - Guard `+inf` fraction weights and redistribute min/max-clamped
     remainder (`1.16`).
   - Preserve `SizingMode.fixed` cross-axis size under `AlignItems.stretch`
     (`1.16`).
   - Avoid cache-busting `updateFlexChildTextHeight` on unchanged row
     children (`2.4`).
   - Group >5 params and fix scoped import indentation (`5.2`).
4. **`layout_text.d` (`1.11`, `1.16`, `2.4`, `5.1`, `6.2`)**:
   - Add `forceEllipsis` truncation helper for multiline vertical overflow
     so the last line never drops `"..."` (`1.11`).
   - Preserve leading indentation and whitespace-only lines in `wrapLine`,
     and guard `NaN` width in `truncateWithEllipsis` (`1.16`).
   - Fast-path `sanitizeSingleLine` when no `\r`/`\n` exists, eliminate GC
     `boundaries` + `~ "..."` churn, fix O(N^2) `breakLongWord`, and avoid
     discarding `FormattedTextLine[]` in `measureTextContentSize` (`2.4`).
   - Use param struct for 7-8 param functions, `private:` section, 2-space
     import indent (`5.1`), and add overflow/NaN/UTF-8 tests (`6.2`).
5. **`layout_system.d`, `layout_anchor.d`, `layout_dimension.d`, `layout_axis.d`, `scroll_system.d` (`1.16`, `2.4`, `3.1`, `4.1`-`4.2`, `5.1`-`5.2`, `6.2`)**:
   - `layout_system.d`: re-measure auto-height flex parents after wrapped
     text changes child height, clear `childBuf` refs (`1.16`), remove
     duplicate `alignChildCrossAxis` pass (`2.4`), delete dead `CustomLayout`
     (`3.1`), rename overloaded `handleSizeComp`/`handleAnchorComp`, remove
     default `Renderer r = null`, fix visibility/6-param/top-import style
     (`5.1`).
   - `layout_anchor.d`: unify horizontal/vertical anchor helpers (`4.1`) and
     remove `layout_flex` import (`3.1`), document nullable param (`3.2`).
   - `layout_dimension.d`: clamp `NaN`/`+inf` (`1.16`) & group >5 params
     (`5.2`). `layout_axis.d`: prune unused imports (`5.2`).
   - `scroll_system.d`: guard non-finite `sa.offset` when `!clampOffset`
     (`1.16`), fix import indent (`5.2`), use `MockWidgetSystemHost` (`4.2`),
     and add empty/NaN/anchored tests (`6.2`).

## Verification

- `rdmd .agents/skills/build-and-test/scripts/run_verify.d --checks`
