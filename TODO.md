- In guidemo implement new virtual (to reperesent large data sets dynamically by
  recycling widgets) vertical/horizontal list composit control with scrollbars,
  which may contain multiple types of elements (widgets) (types are represented
  as array of strings, fixed at creation), which have a variable size (the size
  may exceed visible area of the parent control). Implementation is placed into
  `virtlist.d` and may be similar to `tabcontrol.d`, where the model defines
  just items count, current page location, etc, actual row/column data to setup
  the row widget is up to the provider of the factory methods for reusable
  widgets per row/column. Either extend existing or implement new WidgetSystem
  to handle resizing and scrolling cooperation to support dynamic list items
  removal/insertion maintaining relative scroll position, and notification that
  the widget is no longer visible/cached for recycling later, so the provider be able to
  stop animation logic for it. Implement a new page in guidemo to demostrate heterogeneous
  list with dynamic grows/removal, and very larget sets, e.g. 10000 items to test
  proper scrolling, positioning and rendering. The list is developed to be employed
  to render file lists (open/save file browser), media collection (animated video clips with
  metadata mixed with image thumbnails with exif) and similar cases both vertical and horizontal.

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
