- timers, controllers, systems update architecture simplification and
  improvement based on documentation/timers-and-systems.md Variant D hybrid idea:

  timers must have owners (class instance passed on registration), TimerService
  must have a method that unregisters all timers that are bound to passed owner
  instance, start* methods are reduced to single one that accepts owner object;

  id = DefaultController.startTimer(...no callback) -- uses UiSystem, UiSystem unregisters it on popController
  Controller.onTimer(TimerId, dt) -- called for all timers fired for that controller independently (i.e. may be called multiple times for different firing timers in a single update step (like Controller.tick in current code),
  body may use sendUpdate if something needs updating (logic recalc or view), or may
  request view update at once during the update phase (e.g. to update animations preemptively no matter
  how full the event queue is), however
  usually only Controller.update() is meant to schedule updateView -- add doc comments to Controller interface.

  Implement similar Controller pattern to WidgetSystem timers -- single onTimer method etc.

  startCallbackTimer must be removed.


- guidemo: text hint popup layer widget, controller, system and component with
hint displayed and animated transparency when cursor delays over a control to
display the full text (currently buttons do not fit the whole text

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
