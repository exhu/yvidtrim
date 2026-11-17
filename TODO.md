- implement scroll bar composit widget for vertical and horizontal scroll
bars. Add new module scrollbars.d in source/guidemo.  Implement a controller and
builder function or struct that returns root widget.  Controller should be
registered in UiSystem (see tabcontrol.d). Scrollbar must be resizable, it
consists of left/right (or top/bottom) arrow buttons a free area between them
which holds a bar button that is a rectangle that is movable by mouse dragging
to display or select current position. Min, max, current value, visible window size
in units of min/max/value (to calculate relative size of the drag bar to the free area), are tracked via
VersionedModel (see TabsModel as example), also there's option to report position change only after mouse is released (in order to not spam the events per every pixel moved). Support mouse drag event with possible cursor
capture (implement necessary WidgetComponents). Mouse clicks on free area move page up/down (page size = visible window size from the model). Root scrollbar container has a View
component that translates button events to capture by the scrollbar controller. The controller sends update events to inform about position change. Draggable bar
changes its size to express how much of scrolling is available relative to the
viewable area, has a minimum size to be visible.

- Dynamic lists are for another feature to implement.



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
