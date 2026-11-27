# Phase 2: Rename `get*`/`set*` Symbols in yguilib

Rename the remaining accessor-style symbols under `yguilib/source/yguilib/`
(and their users in `source/`) to `codestyle.md` names.

## Rules & Conventions
- Read `codestyle.md` and `AGENTS.md` first. 2-space indent, max 80 cols.
- Use the `rename-symbol` skill
  (`rdmd .agents/skills/rename-symbol/scripts/rename_symbol.d`): dry-run,
  check collisions, then `--apply`. Use `--owner`/`--member-only` for
  methods with common names. Repeat for `.agents/skills` with
  `--include-skills` and docs with `--include-docs` (skip `*/archive/*`).
- Property pairs: `T x() const` + `void x(T v)`; rename a clashing field to
  `fX` (make it private if it was only reached via the accessors).
- If a suggested name collides (local, parameter, field, `std` symbol),
  pick `<returnMeaning>From<ArgMeaning>` or another verb and record it in
  the table below in the final report.
- Do not touch `__traits(getMember, ...)`, `Thread.getThis()`, C wrapper
  symbols, or `documentation/archive/`, `plans/archive/`.
- Build/test after each group:
  `ninja -C _build && timeout 300 meson test -C _build`.

## Renames

```
file (yguilib/source/yguilib/)  old                         new
------------------------------  --------------------------  ---------------------------
window.d                        getDefaultScaling           defaultScaling
window.d                        getUnitsScaling/set...      unitsScaling pair (fUnitsScaling)
window.d                        getDisplayScaling/set...    displayScaling pair
window.d                        setSize(w, h)               resize
window.d                        setTextInputArea            updateTextInputArea
internal/uisystem_impl.d        same scaling accessors      same as window.d
internal/uisystem_impl.d        setEventStatsEnabled        eventStatsEnabled (setter)
uisystem.d                      setEventStatsEnabled        eventStatsEnabled (setter)
internal/uisystem_impl.d        setTimerClock               timerClock (setter)
internal/uisystem_impl.d        getActiveControllerOrNull   activeControllerOrNull
internal/uisystem_impl.d        getAppEvent                 nextAppEvent
internal/uisystem_impl.d        getControllerName           controllerName
internal/timer_service.d        setClock                    clock (setter)
events/internal/message_bus.d   setStatsEnabled             statsEnabled (setter)
events/internal/message_bus.d   getStats                    queueStats
controller/package.d            setModal / isModal          modal pair (setter + getter)
controller/internal/            getActiveOrNull             activeOrNull
  controller_stack.d            getAll                      controllers
object_registry.d               getByName                   findByName
timers.d                        setPause                    paused pair (fPaused)
timers.d                        getDuration/setDuration     duration pair (fDuration)
timers.d                        getProgress                 progress
widget/system.d                 setPriority                 priority (setter)
widget/package.d                getContentArea              contentArea
widget/widget_view.d            getControllerName           controllerName
widget/widget_view.d, builder.d getWidgetViewName           widgetViewName
widget/virtlist_components.d    setCrossOffset              requestCrossOffset
widget/internal/layout_axis.d   getMainSize, getCrossSize   mainSize, crossSize
                                getMain/CrossMarginStart    mainMarginStart, ...
                                getMain/CrossMarginEnd      mainMarginEnd, ...
                                getMain/CrossOuterSize      mainOuterSize, ...
                                setMainSize, setCrossSize   assignMainSize, assignCrossSize
                                setMainPos, setCrossPos     assignMainPos, assignCrossPos
widget/internal/layout_text.d   getLineStep                 lineStepFromFont
                                getFirstLineHeight          firstLineHeightFromFont
widget/internal/                getBorderWidth              borderWidthFromComponent
  layout_content_size.d
widget/internal/                getLayoutLines              layoutLines
  text_label_cache.d            getTextContentSize          textContentSize
widget/internal/                getEstimatedItemMainSize    estimatedItemMainSize
  virtlist_system.d
controls/button.d               setButtonRestColors         applyButtonRestColors
controls/button.d               setActive(w, host)          trackActiveButton
controls/composite_view.d       setBuilderModel             assignBuilderModel
                                setBuilderTracker           assignBuilderTracker
                                getEntryField               entryField
controls/internal/axis.d        setFixedCrossSize           applyFixedCrossSize
controls/scrollbars.d           setMetrics                  updateMetrics
                                getDecButton, getIncButton  decButton, incButton
                                getTrack, getThumb          track, thumb
                                getEventName                eventName
                                getTrackMainLength          trackMainLength
controls/tooltip.d              setTiming                   timing (setter)
controls/virtlist.d             getViewport                 viewport
                                getMainScrollbar            mainScrollbar
                                getCrossScrollbar           crossScrollbar
                                getEventName                eventName
                                getDefaultItemMainSize      defaultItemMainSize
controls/tabcontrol.d           getLeftButton, getRight...  leftButton, rightButton
                                getScrollViewport           scrollViewport
                                getTabsContainer            tabsContainer
                                setArrowsVisible            showArrows
                                getScrollMetrics            scrollMetrics
                                setActive (unittest local)  activateTab
```

Notes:
- Renaming an interface method (`Controller.setModal`,
  `UiSystem.setEventStatsEnabled`, `getControllerName`, `getWidgetViewName`)
  also renames every `override` in `source/guidemo/` (e.g.
  `hover_button.d:702`) and the reference in
  `.agents/skills/define-gui-widget/scripts/define_gui_widget.d`.
- `isModal` has many users; rename it together with `setModal` so the pair
  is `modal()` / `modal(bool)`.
- `scrollbars.d` `entry.track`/`entry.thumb` fields exist; methods on the
  view class are distinct, but check the collision report.

## Verification
```bash
ninja -C _build && timeout 300 meson test -C _build
grep -rnE '\b(get|set)[A-Z]' yguilib/source   # only getMember/getThis
rdmd .agents/skills/check-line-length/scripts/check_line_length.d
rdmd .agents/skills/check-codestyle/scripts/check_style.d
rdmd .agents/skills/define-gui-widget/scripts/define_gui_widget.d --audit
```
