# guidemo-conform phase 4: virtlist page + ARCHITECTURE.md

Overview: [guidemo-conform.md](guidemo-conform.md). Read `codestyle.md`,
`AGENTS.md` first. Phases 1-3 done; `scrollbars_page.d` /
`scrollbars_controller.d` show the `<X>PageTrackers` + 
`PageControllerParams` pattern to copy.

## Rule
A model the controller modifies is passed to both and edited by the
controller via its tracker; models used only by the view stay in the view.

## Steps
1. Extract item data arrays from `VerticalMediaProvider` and
   `HorizontalStripProvider` (`pages/virtlist_page.d`) into
   `VersionedModel` classes `VerticalItemsModel` / `HorizontalItemsModel`
   (with insert/remove/reset/toggle-expand/resize helpers as model methods)
   in new module `pages/virtlist_items.d` (also `VerticalItemData`,
   `HorizontalItemData`, kinds, `ItemDimensions` if they are data).
   Providers receive the item trackers (copied via `from`) and read items
   in `updateWidgetAt`; they keep only widget/pool/animation state.
2. `VirtListPageTrackers`: page model, `vList`/`hList` (`VirtListModel`),
   `vItems`/`hItems`. View ctor `(ui, parent, ref VirtListPageTrackers)`
   (drop `UiRegistry` param); controller via `PageControllerParams`.
   Remove `getTracker()`, `createStandalone()`.
3. Move into `VirtListPageController` (editing trackers directly):
   `insertAboveViewport`, `insertAtCurrent`, `removeAtCurrent`,
   `toggleVerticalCount`, `jumpToMiddle`, `expandVisibleRow`,
   `resizeHorizontalItem`, `insertHorizontalClip`, `removeHorizontalClip`,
   `narrowHorizontalViewport`, `widenHorizontalViewport`,
   `resetHorizontalList`. Viewport width goes into a model field; the view
   applies it in `update()`.
4. Telemetry (`syncTelemetry`, reads VirtListComponent counters) and video
   animation ticking may stay view-side (view-only state); the controller
   keeps timer start/stop so `SDL_WaitEvent` idles at 0% CPU when no
   videos animate.
5. Split the module: providers -> `pages/virtlist_providers.d`, items ->
   `pages/virtlist_items.d`; `virtlist_page.d` keeps the page view. Add
   new files to `guidemo_lib_src` in top-level `meson.build`.
6. Update `guidemoapp.d`, unittests (incl. harness controllers in
   `virtlist_controller.d`).
7. Update ARCHITECTURE.md guidemo section: list `common.d`, `model.d`,
   `view.d`, `demo_model_helpers.d`, the new virtlist modules, and one line
   on the page wiring pattern (trackers created in `registerDemoPages`,
   passed to page view + controller via `PageControllerParams`; view-only
   models stay inside views). Also fix any stale names (e.g.
   `tooltip()` builder methods). Keep < 250 lines:
   `rdmd .agents/skills/check-line-length/scripts/check_line_length.d \
   -f --max-lines 249 ARCHITECTURE.md`.

## Verify
`ninja -C _build && meson test -C _build` and the 4 check skills from the
overview.
