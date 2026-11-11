- add Widget.name string field which can help debug widget tree (the name
is not unique, there may be any amount of widgets sharing the same name in
the tree).

- add a coding style rule to create only one constructor per class, no overloading,
and fix WidgetBuilder class to have only one minimal constructor. Find other
classes that have multiple constructors and refactor to minimize.

- add dumpTree debug function for a Widget to dump widget tree in readable json
format with all widget fields, component fiels, sizes and positions, children etc.
It should dump everything in order to easily debug layout bugs.

- add UiSystem.dumpInfo to dump controller stack, registered views,
windows and windows' root widget name and ID.

- add skill to author gui based on tabControl changes

- Dynamic lists are for another feature to implement.

- registerViewWidget must be supported with unregister on widget removal from a tree.
Rethink widget life time, may be it's constructor must not append to parent.
see `documentation/widget_lifetime_and_ownership_plan.md`:
root marker for Window root widget? (to allow to exist with null parent);
should removing from parent cause unsubscription and unregistring, or only dispose() method
does that? UiSystem.releaseWidget(w) instead of hooks and handlers in the Widget itself?

- may be just use ViewComponent on root widget + WidgetView +
WidgetViewController in demo and everywhere for consistency instead of manually
created View and Controller?



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
