- how active animations are updated? input events and animation updates conflict.

runEventLoopStep() in uisystem_impl sends AppEvent.Kind.update if timeout.
However Controller.update is called only via handleEvent when there's
Kind.update event received, and this will not be received while there are other
events in the queue, e.g. massive mouse movement saturates the queue and
animation is not going forward, or becomes lagging. Returning Result.update to
any input event will fill the queue with updates and now the app is not
responsive to input events. So Controller.handleEvent is the only point where
timers and animation model can be updated either via AppEvent.Kind.update, or
just via calling update() and Result.updateView. This problem is visible in
`guidemo/pages/layout_painter_controller.d` maybe support timers as new events
in MessageBus to wake the system instead of uninterrupted loop of result updates
in handleEvent, so that any controller can forget about timeOut value for event,
which then will be set by UiSystem based on the nearest timer to fire?
Another option is to have a priority queue in MessageBus, where some events (e.g. update) may
have precedence over other events in a defined proportion, e.g. if there's an event with
a timeout field not -1, then make sure it gets handled earlier than current queue up to that event.


- decide on view-controller architecture, View should be created before the controller
and passed to it instead of creating a view inside one.

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
