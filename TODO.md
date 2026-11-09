- make tabs in guidemo (top page selection) with scrolling using ScrollableArea component via
a new controller and added left and right arrow buttons, scrolling jumps by tab button origins
TODO: need to think how to identify the offset steps.
Fast scrolling (without animation, just switching which tab button is the
first visible may be implemented just by changing visibility of buttons (hide
all until the current left-most).

```
TabControlWidget (with ViewComponent)
 - flex container
  - left button
  - scrollable area (has children clipping on)
   - movable control which may be larger than visible area of the parent in order to align leftmost or rightmost children.
   has WidgetArrayComponent to display widgets to cover visible area (can produce more widgets to cover all visible parent area)
  - right button.

[<][tab1][ta...][>]
```

Scroll area seems to be a separate components: scroll container moves child container.
Child container needs to resize to be larger than scroll container, needs to know current
position, layout size children produced by its WidgetArrayComponent.

We don't know how many WidgetArrayComponent items to request before layout is complete.
Maybe introduce a layout component that will notify if the space is available
or lacks?

Clipped list cells can be excluded from layout because of considered invisible,
need to add a component or flag that the widget is included in visible list even
if it is clipped (includes the whole tree into visible list).

a scroll list may just append new widgets on container resize,
but on shrink just hide unnecessary, then reuse already allocated on scrolling
and on growing.

with FlexContainer component it can produce horizontal or vertical lists.

There may be two kind of scrollers: constructed widget hierarchy, dynamically
constructed (as a window into large data set).

Browsing large data set is way complicated, so let's implement tabs as a
fixed hierarchy which is scrollable via just moving the container inside
a clipping parent. However need to check if clipped widgets still included
in layout process, if they are not then we need to resolve it.

Dynamic lists are for another feature to implement.

- registerViewWidget must be supported with unregister on widget removal from a tree.
Rethink widget life time, may be it's constructor must not append to parent.
see `documentation/widget_lifetime_and_ownership_plan.md`:
root marker for Window root widget? (to allow to exist with null parent);
should removing from parent cause unsubscription and unregistring, or only dispose() method
does that? UiSystem.releaseWidget(w) instead of hooks and handlers in the Widget itself?

- may be just use ViewComponent on root widget + WidgetView +
WidgetViewController in demo and everywhere for consistency instead of manually
created View and Controller?

- Use TabControl in guidemo to replace current tab1btn, tab2btn etc


- Systems and components satisfy the case of parent and child widgets and
multitude of instances, while WidgetController may be more appropriate when
multiple Widgets are at play, e.g. a scrollable list may be implemented
with (root (scroll-view-container (contents...))(scroll-bar)), so it must
listen to events of scroll-bar and scroll-view on contents size change or
also it must accept an array model and pass it to scroll-view-container.

- To make lists scrollable we need additional component ScrollviewComponent, which
expects a single child Widget that it moves and sends event when size of the
child or its own size changed.

- make combobox switch in guidemo (no more space to insert buttons)
and/or scrollable tab panel

- first devise reusable composite widgets in code (how to pass models, events,
reusable views and controllers), then we'll invent a text format to construct
widget trees to allow for visual editing


- video player component and system is external to yguilib to be independent from ffmpeg

- mouse capture component to capture mouse (and hide cursor) to implement
knobs
- build widget library
-- button with hover
-- combobox
- styles
- add image support

- assets management (transparent mapping to embedded import string and file stream data)
- extended font management (proper name, styles)
- define modal controller rules (some controllers must still handle events, when modal is active)
- add modal dialog displayed by model on key (and closed by click)
- button
- focus
- modal dialog
- text input

------------
Noted for future, discarded for now:
looks like does not fit the proper paradigm, it should be a system rather than
a controller for multiple controls like hover effect, however can be used
to accept data model name and resolve field names to controls:
	- WidgetViewController to support controllers that only need Widget as a view and
	registered via registry. --
	- addView method may support multiple Views or error if already added view

- add named controller registry and wiring logic, so that View.addToController is used
instead of manually adding views to controllers for HoverButton
- check if it's ergonomically better
- the controller stack is still manipulated manually by the code (View components do not push/pop them),
however named controllers should be created in advance and live in the runtime registry.

- discarded for now:
	- composite controller? e.g. a modal dialog owns several controllers so that the stack can skip
	all events when a modal controller is active?
	- add to View component controller name, so user registers a map of controllers and then
	views and controllers are automatically pushed -- can be problematic if the widget should be
	visible but change behaviour? Modal component?

	if view requests controller push, and controller can hide view, then there's cycle.
