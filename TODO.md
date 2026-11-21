- Dynamic virtual list control is for another feature to implement.
Implement a new page in guidemo that shows new virtual list
composite control. Implement that control in a new module similar to
`scrollbars.d`, `tabcontrol.d`. Virtual list control is a composite control
that accepts a new interface similar how TabButtonsProvider works which
provides new widgets to construct. However virtual list must support
scrollbars, item selection (single optional (can be no item selected), single, or multiple, no selection possible),
items may be of different kinds, e.g. a list may be constructed from
different data that is represented by different composite widgets itself,
e.g. a list of media data may represent each row differently based on
type of media: video widget (animated thumbnail and info text), image (thumb and different set
of controls, e.g. tags, exif data), generic file. So the factory interface
should provide a reusable widget for a requested row type. All possible row types
are identified with strings and passed to the virtual list model, which only
guides the control: number of row types, selections, amount of items in the list etc. The real data model is
not necessary for the widget, it's known implementation to the provider only, the factory methods (create and update) would accept the row type, selection state, index.


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
