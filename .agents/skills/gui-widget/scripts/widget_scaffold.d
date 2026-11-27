/**
 * Scaffolds new GUI widget builders (inline, view, or system tier).
 */
module widget_scaffold;

import std.array : appender, replace;
import std.ascii : toLower;
import std.file : exists, mkdirRecurse, write;
import std.path : dirName;
import std.stdio : stderr, writefln, writeln;

struct ScaffoldOptions {
  string name = null;
  string tier = "inline";
  string modName = null;
  string outPath = null;
  bool dryRun = false;
}

int runScaffoldCommand(in ScaffoldOptions opts) {
  if (opts.tier != "inline" && opts.tier != "view" && opts.tier != "system") {
    stderr.writeln("Error: --tier must be 'inline', 'view', or 'system'.");
    return 1;
  }
  const string modName = (opts.modName !is null && opts.modName.length > 0)
    ? opts.modName
    : "yvidtrim." ~ toSnakeCase(opts.name);
  const string outPath = (opts.outPath !is null && opts.outPath.length > 0)
    ? opts.outPath
    : derivePathFromModule(modName);

  const string code = generateScaffold(opts.name, modName, opts.tier);
  if (opts.dryRun) {
    writefln("// --- DRY RUN: %s (tier: %s) ---", outPath, opts.tier);
    writeln(code);
    return 0;
  }
  if (exists(outPath)) {
    stderr.writefln("Error: File '%s' already exists.", outPath);
    return 1;
  }

  const string parentDir = dirName(outPath);
  if (parentDir.length > 0 && !exists(parentDir)) {
    mkdirRecurse(parentDir);
  }
  write(outPath, code);
  writefln(
    "Scaffolded %s (%s tier) -> %s",
    opts.name,
    opts.tier,
    outPath
  );
  return 0;
}

private:

string toCamelCase(string pascal) {
  if (pascal.length == 0) {
    return "widget";
  }
  return [cast(char) toLower(pascal[0])].idup ~ pascal[1 .. $];
}

string toSnakeCase(string pascal) {
  auto buf = appender!string();
  foreach (i, char c; pascal) {
    if (c >= 'A' && c <= 'Z') {
      if (i > 0) {
        buf.put('_');
      }
      buf.put(cast(char) toLower(c));
    } else {
      buf.put(c);
    }
  }
  return buf.data;
}

string derivePathFromModule(string modName) {
  import std.algorithm : startsWith;

  const string rel = modName.replace(".", "/") ~ ".d";
  if (modName.startsWith("yguilib.")) {
    return "yguilib/source/" ~ rel;
  }
  return "source/" ~ rel;
}

string applyPlaceholders(
  string tmpl,
  string widgetName,
  string camelName,
  string modName
) {
  return tmpl
    .replace("__SNAKE__", toSnakeCase(widgetName))
    .replace("__NAME__", widgetName)
    .replace("__CAMEL__", camelName)
    .replace("__MOD__", modName);
}

string generateScaffold(string widgetName, string modName, string tier) {
  const string camelName = toCamelCase(widgetName);
  if (tier == "view") {
    return applyPlaceholders(
      viewTemplatePart1() ~ viewTemplatePart2(),
      widgetName,
      camelName,
      modName
    );
  }
  if (tier == "system") {
    return applyPlaceholders(
      systemTemplatePart1() ~ systemTemplatePart2(),
      widgetName,
      camelName,
      modName
    );
  }
  return applyPlaceholders(
    inlineTemplatePart1() ~ inlineTemplatePart2(),
    widgetName,
    camelName,
    modName
  );
}

string inlineTemplatePart1() {
  return
`/**
 * __SNAKE__.d - Reusable __NAME__ widget builder and configuration.
 */
module __MOD__;

import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.layout_components : AlignItems, JustifyContent;

/// Visual styling and sizing configuration for __NAME__.
struct __NAME__Style {
  float width = 160.0f;
  float height = 36.0f;
  float cornerRadius = 6.0f;
  float fontSize = 13.0f;
  ColorF bg = ColorF(0.14f, 0.16f, 0.22f, 1.0f);
  ColorF border = ColorF(0.28f, 0.32f, 0.42f, 1.0f);
  ColorF text = ColorF(0.95f, 0.95f, 0.95f, 1.0f);
}

/// Fluent builder constructing a __NAME__ widget tree.
struct __NAME__Builder {
  ref __NAME__Builder name(string controlName) return {
    widgetName = controlName;
    return this;
  }

  ref __NAME__Builder caption(string text) return {
    labelText = text;
    return this;
  }

  ref __NAME__Builder style(in __NAME__Style s) return {
    cfg = s;
    return this;
  }

  ref __NAME__Builder event(string customEventName) return {
    eventName = customEventName;
    return this;
  }
`;
}

string inlineTemplatePart2() {
  return
`
  /// Builds the __NAME__ widget tree. parent may be null in isolated tests.
  Widget build(UiSystem ui, Widget parent, RectF rect) {
    assert(ui !is null, "ui must not be null");
    const string rootName = (widgetName.length > 0) ? widgetName : "__CAMEL__";

    auto root = WidgetBuilder.make(ui)
      .parent(parent)
      .name(rootName)
      .rect(rect)
      .fixedSize(cfg.width, cfg.height)
      .paddingVh(4, 10)
      .flexRow()
      .gap(8.0f)
      .justify(JustifyContent.center)
      .alignItems(AlignItems.center)
      .roundBg(cfg.bg)
      .bgRadius(cfg.cornerRadius)
      .border(cfg.border)
      .borderWidth(1.0f)
      .onMouseDown(eventName)
      .build();

    WidgetBuilder.make(ui)
      .parent(root)
      .name(rootName ~ "Label")
      .autoSize()
      .text(labelText)
      .textColor(cfg.text)
      .fontSize(cfg.fontSize)
      .textAlign(TextLabel.Alignment.center)
      .build();

    return root;
  }

private:
  __NAME__Style cfg;
  string widgetName = null;
  string labelText = "__NAME__";
  string eventName = "__CAMEL__Action";
}

unittest {
  import yguilib.uisystem : makeHeadlessUiSystem;
  import yguilib.widget.layout_components : SizingMode;

  auto ui = makeHeadlessUiSystem();
  __NAME__Builder b;
  auto root = b
    .name("test__NAME__")
    .caption("Sample")
    .build(ui, null, RectF(0, 0, 160, 36));

  assert(root !is null);
  assert(root.name == "test__NAME__");
  assert(root.children.length == 1);
  assert(root.components.size !is null);
  assert(root.components.size.width.mode == SizingMode.fixed);

  void verifyAllNamed(Widget w) {
    assert(w.name.length > 0, "Widget missing name");
    foreach (child; w.children) {
      verifyAllNamed(child);
    }
  }
  verifyAllNamed(root);
}
`;
}

string viewTemplatePart1() {
  return
`/**
 * __SNAKE__.d - Composite __NAME__ widget, WidgetView, and Controller.
 */
module __MOD__;

import yguilib.controller : HandleResult;
import yguilib.events : AppEvent;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.layout_components : AlignItems, JustifyContent;
import yguilib.widget.widget_view : WidgetView, WidgetViewBase,
  WidgetViewControllerBase;

enum __CAMEL__ChildClickEvent = "__CAMEL__ChildDown";
enum default__NAME__EventName = "__CAMEL__Action";
enum __CAMEL__WidgetViewName = "__NAME__WidgetView";
enum __CAMEL__WidgetViewControllerName = "__NAME__WidgetViewController";

/// Visual styling for __NAME__.
struct __NAME__Style {
  float width = 180.0f;
  float height = 36.0f;
  float cornerRadius = 6.0f;
  float fontSize = 13.0f;
  ColorF bg = ColorF(0.14f, 0.16f, 0.22f, 1.0f);
  ColorF border = ColorF(0.28f, 0.32f, 0.42f, 1.0f);
  ColorF text = ColorF(0.95f, 0.95f, 0.95f, 1.0f);
}

/// WidgetView managing registered __NAME__ root widgets and event translation.
final class __NAME__WidgetView : WidgetViewBase {
  override void translateEventForViewWidget(
    ref AppEvent sourceEvent,
    Widget viewWidget
  ) {
    assert(viewWidget !is null, "viewWidget must not be null");
    super.translateEventForViewWidget(sourceEvent, viewWidget);
  }
}

/// WidgetViewController servicing translated __NAME__ view events.
final class __NAME__WidgetViewController : WidgetViewControllerBase {
  this(UiSystem uiSystem) {
    assert(uiSystem !is null, "uiSystem must not be null");
    super(uiSystem);
  }

  override HandleResult handleEvent(AppEvent ev) {
    if (ev.kind == AppEvent.Kind.view && ev.view.viewWidget !is null) {
      foreach (v; views) {
        if (v.isWidgetRegistered(ev.view.viewWidget)) {
          return HandleResult(HandleResult.Result.updateView, false);
        }
      }
    }
    return super.handleEvent(ev);
  }
}

/// Registers __NAME__WidgetView and __NAME__WidgetViewController in ui.
__NAME__WidgetViewController register__NAME__(UiSystem ui) {
  assert(ui !is null, "ui must not be null");
  auto view = new __NAME__WidgetView();
  auto ctrl = new __NAME__WidgetViewController(ui);
  ctrl.registerWidgetView(view);
  ui.widgetViews.register(view.widgetViewName(), view);
  ui.widgetViewControllers.register(ctrl.controllerName(), ctrl);
  return ctrl;
}
`;
}

string viewTemplatePart2() {
  return
`
/// Fluent builder constructing a composite __NAME__ widget tree.
struct __NAME__Builder {
  ref __NAME__Builder name(string controlName) return {
    widgetName = controlName;
    return this;
  }

  ref __NAME__Builder event(string customEventName) return {
    eventName = customEventName;
    return this;
  }

  ref __NAME__Builder style(in __NAME__Style s) return {
    cfg = s;
    return this;
  }

  /// Builds the composite widget. parent may be null in isolated tests.
  Widget build(UiSystem ui, Widget parent, RectF rect) {
    assert(ui !is null, "ui must not be null");
    const string rootName = (widgetName.length > 0) ? widgetName : "__CAMEL__";
    const string targetEv = (eventName.length > 0)
      ? eventName
      : default__NAME__EventName;

    string[string] renameMap;
    renameMap[__CAMEL__ChildClickEvent] = targetEv;

    auto root = WidgetBuilder.make(ui)
      .parent(parent)
      .name(rootName)
      .rect(rect)
      .fixedSize(cfg.width, cfg.height)
      .flexRow()
      .gap(8.0f)
      .justify(JustifyContent.center)
      .alignItems(AlignItems.center)
      .roundBg(cfg.bg)
      .bgRadius(cfg.cornerRadius)
      .border(cfg.border)
      .borderWidth(1.0f)
      .viewEvents(renameMap)
      .viewName(__CAMEL__WidgetViewName)
      .build();

    WidgetBuilder.make(ui)
      .parent(root)
      .name(rootName ~ "Btn")
      .size(cfg.width, cfg.height)
      .autoSize()
      .text(rootName)
      .textColor(cfg.text)
      .fontSize(cfg.fontSize)
      .textAlign(TextLabel.Alignment.center)
      .onMouseDown(__CAMEL__ChildClickEvent)
      .build();

    return root;
  }

private:
  __NAME__Style cfg;
  string widgetName = null;
  string eventName = default__NAME__EventName;
}

unittest {
  import yguilib.uisystem : makeHeadlessUiSystem;

  auto ui = makeHeadlessUiSystem();
  auto ctrl = register__NAME__(ui);
  assert(ctrl !is null);

  __NAME__Builder b;
  auto root = b
    .name("test__NAME__")
    .event("customEv")
    .build(ui, null, RectF(0, 0, 180, 36));

  assert(root !is null);
  assert(root.components.view !is null);
  assert(
    root.components.view.renameEvents[__CAMEL__ChildClickEvent] == "customEv"
  );

  void verifyAllNamed(Widget w) {
    assert(w.name.length > 0, "Widget missing name");
    foreach (child; w.children) {
      verifyAllNamed(child);
    }
  }
  verifyAllNamed(root);
}
`;
}

string systemTemplatePart1() {
  return
`/**
 * __SNAKE__.d - ECS-style __NAME__ component, builder, and WidgetSystem.
 */
module __MOD__;

import yguilib.events : AppEvent;
import yguilib.render.render_types : ColorF, RectF;
import yguilib.uisystem : UiSystem;
import yguilib.widget : Widget;
import yguilib.widget.builder : WidgetBuilder;
import yguilib.widget.component : WidgetComponent;
import yguilib.widget.drawing_components : TextLabel;
import yguilib.widget.system : SystemEventResult, SystemPhase, WidgetSystem,
  WidgetSystemContext;

/// Visual styling for __NAME__.
struct __NAME__Style {
  float width = 140.0f;
  float height = 34.0f;
  float cornerRadius = 6.0f;
  float fontSize = 13.0f;
  ColorF bg = ColorF(0.16f, 0.18f, 0.24f, 1.0f);
  ColorF border = ColorF(0.30f, 0.35f, 0.45f, 1.0f);
  ColorF text = ColorF(0.95f, 0.95f, 0.95f, 1.0f);
}

/// ECS WidgetComponent attached to __NAME__ widgets.
final class __NAME__Component : WidgetComponent {
  string actionEvent;

  this(string actionEvent) {
    this.actionEvent = actionEvent;
  }
}

/// Fluent builder constructing a single-node __NAME__ widget.
struct __NAME__Builder {
  ref __NAME__Builder name(string controlName) return {
    widgetName = controlName;
    return this;
  }

  ref __NAME__Builder caption(string text) return {
    labelText = text;
    return this;
  }

  ref __NAME__Builder style(in __NAME__Style s) return {
    cfg = s;
    return this;
  }

  ref __NAME__Builder action(string eventName) return {
    actionEvent = eventName;
    return this;
  }
`;
}

string systemTemplatePart2() {
  return
`
  /// Builds the widget. parent is allowed to be null in isolated tests.
  Widget build(UiSystem ui, Widget parent, RectF rect) {
    assert(ui !is null, "ui must not be null");
    const string rootName = (widgetName.length > 0) ? widgetName : "__CAMEL__";

    return WidgetBuilder.make(ui)
      .parent(parent)
      .name(rootName)
      .rect(rect)
      .fixedSize(cfg.width, cfg.height)
      .paddingVh(6, 12)
      .roundBg(cfg.bg)
      .bgRadius(cfg.cornerRadius)
      .border(cfg.border)
      .borderWidth(1.0f)
      .text(labelText)
      .textColor(cfg.text)
      .fontSize(cfg.fontSize)
      .textAlign(TextLabel.Alignment.center)
      .handleInput(true)
      .component(new __NAME__Component(actionEvent))
      .build();
  }

private:
  __NAME__Style cfg;
  string widgetName = null;
  string labelText = "__NAME__";
  string actionEvent = "__CAMEL__Action";
}

/// WidgetSystem processing visible widgets with __NAME__Component.
final class __NAME__System : WidgetSystem {
  this() nothrow @safe {
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.event | SystemPhase.preLayout;
  }

  override SystemEventResult handleEvent(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    return SystemEventResult(false, false);
  }
}

unittest {
  import yguilib.uisystem : makeHeadlessUiSystem;

  auto ui = makeHeadlessUiSystem();
  __NAME__Builder b;
  auto w = b
    .name("test__NAME__")
    .caption("Run")
    .action("onRun")
    .build(ui, null, RectF(0, 0, 140, 34));

  assert(w !is null);
  assert(w.name == "test__NAME__");
  assert(w.components.has!__NAME__Component());
  assert(w.components.get!__NAME__Component().actionEvent == "onRun");
}
`;
}
