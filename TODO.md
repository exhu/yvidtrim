- Add a new page to guidemo to showcase and develop TabControl as primary task of this TODO item.
TabControl is a Widget tree which represents a container for buttons (aka tabs) constructed dynamically based on the model similar to how current `tab_button.d` is
implemented. It accepts a model and maintains a set of buttons synchronized with the model. It posts a custom view event (name provided by the user, e.g. "pageTabSwitch" with a custom payload with the index of the button whose mouseDown event is triggered), the integer is related to the button name in the array inside the model.
TabControl tree managed by WidgetView (button update on model change) and WidgetViewController (reacts to events) in guidemo as tabcontrol.d module.
The control is a set of buttons (see how currently `guidemo/tab_button.d` is used) put into a parent Widget with ViewComponent.
Use WidgetViewBase and WidgetViewControllerBase as base classes from widget_view.d for new TabControlWidgetView and TabControlWidgetViewController final classes used together with ViewComponent of root TabControl Widget to connect tab model (see HeaderTabsModel from guidemo/model.d as example), rename button events and pass custom payload from buttons via WidgetView.translateEventforViewWidget put index of the tab as integer to ViewData.value[0]. Register TabControlWidgetView and TabControlWidgetViewController using UiRegistry interface of UiSystem in guidemo somewhere appropriate in root controller initialization of guidemo app (e.g. when the pages are constructed once in app lifetime).

Make a builder struct to construct that TabControl tree (return Widget root) similar to tabContainer construction in `guidemo/view.d`.


- Use TabControl in guidemo to replace current tab1btn, tab2btn etc
in guidemo which are tab buttons used to switch current page in guidemo/controller.d . Use new event name "tabBtnClicked" instead
of those and pass integer as ViewData.value[0] in event which indicates current
tab number instead of being formatted into event name string.  see
handleViewEvent in source/guidemo/controller.d however there are only strings to
name events e.g. w.componets.mosueEvent.mouseDown, need to add a controller (or
view?) which converts mouseDown with widget pointer to view event with payload.

button.mouseDown -> view event tabBtnClicked -> TabPanelView (controller?) ->
view event tabBtnClicked with tab number -> app review how events are propagated
and how view component is handled.

- explore how to make tabs in guidemo with scrolling
Fast scrolling (without animation, just switching which tab button is the
first visible may be implemented just by changing visibility of buttons (hide
all until the current left-most).

a scroll list may just append new widgets on container resize,
but on shrink just hide unnecessary, then reuse already allocated on scrolling
and on growing.

with FlexContainer component it can produce horizontal or vertical lists.

- registerViewWidget must be supported with unregister on widget removal from a tree.
Rethink widget life time, may be it's constructor must not append to parent.

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
