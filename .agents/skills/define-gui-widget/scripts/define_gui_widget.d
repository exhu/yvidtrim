#!/usr/bin/env rdmd
/**
 * Auditing, discovery, and scaffolding tool for GUI widgets and views.
 *
 * Inspects WidgetBuilder chains across yguilib, guidemo, and yvidtrim for
 * required conventions (.name(...) and .rect(...)), lists custom *Builder
 * structs, and scaffolds new GUI widget builders (inline, view, or system).
 */
module define_gui_widget;

import std.array : appender, array, replace;
import std.ascii : toLower;
import std.file : dirEntries, exists, isFile, mkdirRecurse, readText, SpanMode,
  write;
import std.getopt : defaultGetoptPrinter, getopt, GetoptResult;
import std.path : buildNormalizedPath, dirName, extension;
import std.stdio : stderr, writefln, writeln;
import std.string : format, splitLines, strip;

struct BuilderChain {
  string file;
  size_t startLine;
  size_t endLine;
  string kind; // "WidgetBuilder.make" or ".child"
  bool hasName;
  bool hasRect;
  bool inUnittest;
}

struct CustomBuilderInfo {
  string file;
  size_t line;
  string structName;
}

struct CliOptions {
  bool optAudit = false;
  bool optList = false;
  bool optDryRun = false;
  string scaffoldName = null;
  string tier = "inline";
  string modName = null;
  string outPath = null;
  string filterTarget = null;
}

/**
 * Collects all D source files in the target directories.
 */
string[] collectDSourceFiles(string[] searchDirs) {
  string[] dFiles;
  foreach (dir; searchDirs) {
    if (!exists(dir)) {
      continue;
    }
    foreach (entry; dirEntries(dir, SpanMode.depth)) {
      if (entry.isFile && extension(entry.name) == ".d") {
        dFiles ~= buildNormalizedPath(entry.name);
      }
    }
  }
  return dFiles;
}

/**
 * Scans files for custom *Builder structs (excluding WidgetBuilder and
 * event builders).
 */
CustomBuilderInfo[] scanCustomBuilders(string[] files) {
  import std.algorithm : endsWith;
  import std.regex : ctRegex, matchFirst;

  CustomBuilderInfo[] builders;
  auto structRe = ctRegex!(r"^\s*struct\s+([A-Za-z0-9_]*Builder)\b");

  foreach (file; files) {
    if (!exists(file) || !isFile(file)) {
      continue;
    }
    const string[] lines = readText(file).splitLines();
    foreach (size_t idx, string line; lines) {
      auto m = matchFirst(line, structRe);
      if (!m.empty) {
        const string name = m[1];
        if (name != "WidgetBuilder" && !name.endsWith("EventBuilder")) {
          builders ~= CustomBuilderInfo(file, idx + 1, name);
        }
      }
    }
  }
  return builders;
}

/**
 * Scans files for WidgetBuilder.make(...) and .child(...) chains and checks
 * whether .name(...) and .rect(...) are invoked before the statement ends.
 */
BuilderChain[] scanBuilderChains(string[] files) {
  import std.algorithm : endsWith;

  BuilderChain[] chains;
  foreach (file; files) {
    if (!exists(file) || !isFile(file) || file.endsWith("widget/builder.d")) {
      continue;
    }
    chains ~= scanFileBuilderChains(file, readText(file).splitLines());
  }
  return chains;
}

int main(string[] args) {
  CliOptions opts;
  if (!parseCliArgs(args, opts)) {
    return 0;
  }
  if (opts.scaffoldName !is null && opts.scaffoldName.length > 0) {
    return runScaffoldCommand(opts);
  }
  return runScanCommand(opts);
}

private:

bool parseCliArgs(string[] args, out CliOptions opts) {
  GetoptResult helpInfo;
  try {
    helpInfo = getopt(
      args,
      "audit|a", "Audit WidgetBuilder chains for .name() and .rect()",
        &opts.optAudit,
      "list|l", "List custom *Builder structs and WidgetBuilder chains",
        &opts.optList,
      "scaffold|s", "Scaffold a new GUI widget builder by PascalCase name",
        &opts.scaffoldName,
      "tier|t", "Scaffold tier: inline (default), view, or system",
        &opts.tier,
      "module|m", "D module name for scaffold (e.g. yvidtrim.transport)",
        &opts.modName,
      "output|o", "Output file path for scaffold", &opts.outPath,
      "dry-run|d", "Preview scaffold output without writing to disk",
        &opts.optDryRun,
      "filter|f", "Filter scanned files by substring", &opts.filterTarget
    );
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return false;
  }

  if (helpInfo.helpWanted) {
    defaultGetoptPrinter(
      "Usage: define_gui_widget.d [options]\n\n" ~
      "Audit, list, and scaffold GUI widgets and builders.\n\nOptions:",
      helpInfo.options
    );
    return false;
  }
  return true;
}

int runScaffoldCommand(in CliOptions opts) {
  if (opts.tier != "inline" && opts.tier != "view" && opts.tier != "system") {
    stderr.writeln("Error: --tier must be 'inline', 'view', or 'system'.");
    return 1;
  }
  const string modName = (opts.modName !is null && opts.modName.length > 0)
    ? opts.modName
    : "yvidtrim." ~ toSnakeCase(opts.scaffoldName);
  const string outPath = (opts.outPath !is null && opts.outPath.length > 0)
    ? opts.outPath
    : derivePathFromModule(modName);

  const string code = generateScaffold(opts.scaffoldName, modName, opts.tier);
  if (opts.optDryRun) {
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
    opts.scaffoldName,
    opts.tier,
    outPath
  );
  return 0;
}

int runScanCommand(CliOptions opts) {
  import std.algorithm : canFind, filter;

  if (!opts.optAudit && !opts.optList) {
    opts.optAudit = true;
    opts.optList = true;
  }

  string[] files = collectDSourceFiles(["yguilib/source", "source"]);
  if (opts.filterTarget !is null) {
    files = files.filter!(f => f.canFind(opts.filterTarget)).array;
  }

  auto customBuilders = scanCustomBuilders(files);
  auto chains = scanBuilderChains(files);

  if (opts.optList) {
    printBuilderList(customBuilders, chains);
  }
  if (opts.optAudit) {
    printAuditReport(chains);
  }
  return 0;
}

void printBuilderList(
  in CustomBuilderInfo[] customBuilders,
  in BuilderChain[] chains
) {
  writeln("=== Custom GUI Widget Builders ===");
  foreach (cb; customBuilders) {
    writefln("  %s (%s:%d)", cb.structName, cb.file, cb.line);
  }
  writefln("Total custom builders: %d\n", customBuilders.length);

  size_t prodCount = 0;
  size_t testCount = 0;
  foreach (ch; chains) {
    if (ch.inUnittest) {
      testCount++;
    } else {
      prodCount++;
    }
  }
  writeln("=== WidgetBuilder Chain Summary ===");
  writefln("  Production chains: %d", prodCount);
  writefln("  Unittest chains:   %d", testCount);
  writefln("  Total chains:      %d\n", chains.length);
}

void printAuditReport(in BuilderChain[] chains) {
  writeln("=== WidgetBuilder Convention Audit (Production Code) ===");
  size_t missingNameCount = 0;
  size_t missingRectCount = 0;

  foreach (ch; chains) {
    if (ch.inUnittest) {
      continue;
    }
    if (!ch.hasName) {
      missingNameCount++;
      writefln(
        "  [WARN] %s:%d: %s chain missing .name(...)",
        ch.file,
        ch.startLine,
        ch.kind
      );
    }
    if (!ch.hasRect) {
      missingRectCount++;
      writefln(
        "  [WARN] %s:%d: %s chain missing .rect(...)",
        ch.file,
        ch.startLine,
        ch.kind
      );
    }
  }

  if (missingNameCount == 0 && missingRectCount == 0) {
    writeln("  All production WidgetBuilder chains set .name() and .rect().");
  } else {
    writefln(
      "\nSummary: %d chain(s) missing .name(), %d chain(s) missing .rect().",
      missingNameCount,
      missingRectCount
    );
  }
}

BuilderChain[] scanFileBuilderChains(string file, const string[] lines) {
  import std.algorithm : canFind, startsWith;

  BuilderChain[] chains;
  bool inUnittest = false;
  int braceDepth = 0;
  int unittestBraceDepth = -1;

  foreach (size_t idx, string line; lines) {
    const string trimmed = line.strip();
    if (trimmed.startsWith("unittest") && trimmed.canFind("{")) {
      inUnittest = true;
      unittestBraceDepth = braceDepth;
    }
    updateBraceDepth(line, braceDepth, inUnittest, unittestBraceDepth);

    if (trimmed.startsWith("//") || trimmed.startsWith("*")) {
      continue;
    }
    if (trimmed.canFind("WidgetBuilder.make(")) {
      chains ~= extractChain(
        file,
        lines,
        idx,
        "WidgetBuilder.make",
        inUnittest
      );
    } else if (
      trimmed.canFind(".child(") && trimmed.canFind("WidgetBuilder")
    ) {
      chains ~= extractChildBlock(file, lines, idx, inUnittest);
    }
  }
  return chains;
}

void updateBraceDepth(
  string line,
  ref int braceDepth,
  ref bool inUnittest,
  ref int unittestBraceDepth
) {
  foreach (c; line) {
    if (c == '{') {
      braceDepth++;
    } else if (c == '}') {
      braceDepth--;
      if (inUnittest && braceDepth <= unittestBraceDepth) {
        inUnittest = false;
        unittestBraceDepth = -1;
      }
    }
  }
}

BuilderChain extractChain(
  string file,
  const string[] lines,
  size_t startIdx,
  string kind,
  bool inUnittest
) {
  import std.algorithm : canFind, endsWith;

  bool hasName = false;
  bool hasRect = false;
  size_t endIdx = startIdx;

  for (size_t i = startIdx; i < lines.length && i < startIdx + 45; ++i) {
    const string t = lines[i].strip();
    if (t.canFind(".name(")) {
      hasName = true;
    }
    if (t.canFind(".rect(")) {
      hasRect = true;
    }
    endIdx = i;
    if (t.canFind(".build()") || t.endsWith(";")) {
      break;
    }
  }

  return BuilderChain(
    file,
    startIdx + 1,
    endIdx + 1,
    kind,
    hasName,
    hasRect,
    inUnittest
  );
}

BuilderChain extractChildBlock(
  string file,
  const string[] lines,
  size_t startIdx,
  bool inUnittest
) {
  import std.algorithm : canFind;

  bool hasName = false;
  bool hasRect = false;
  size_t endIdx = startIdx;
  int depth = 0;
  bool opened = false;

  for (size_t i = startIdx; i < lines.length && i < startIdx + 50; ++i) {
    const string t = lines[i].strip();
    if (t.canFind(".name(")) {
      hasName = true;
    }
    if (t.canFind(".rect(")) {
      hasRect = true;
    }
    foreach (c; t) {
      if (c == '{') {
        depth++;
        opened = true;
      } else if (c == '}') {
        depth--;
      }
    }
    endIdx = i;
    if (opened && depth <= 0) {
      break;
    }
  }

  return BuilderChain(
    file,
    startIdx + 1,
    endIdx + 1,
    ".child",
    hasName,
    hasRect,
    inUnittest
  );
}

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
import yguilib.uisystem : UiRegistry, UiSystem;
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
  /**
   * Builds the __NAME__ widget tree.
   * parent and registry are allowed to be null in isolated tests.
   */
  Widget build(
    UiSystem ui,
    Widget parent,
    RectF rect,
    UiRegistry registry = null
  ) {
    assert(ui !is null, "ui must not be null");
    const string rootName = (widgetName.length > 0) ? widgetName : "__CAMEL__";

    auto root = WidgetBuilder.make(ui)
      .parent(parent)
      .name(rootName)
      .rect(rect)
      .fixedSize(cfg.width, cfg.height)
      .padding(4, 10)
      .flexRow(8.0f, JustifyContent.center, AlignItems.center)
      .roundBackground(cfg.bg, cfg.cornerRadius)
      .border(cfg.border, 1.0f)
      .onMouseDown(eventName)
      .build();

    WidgetBuilder.make(ui)
      .parent(root)
      .name(rootName ~ "Label")
      .rect(RectF())
      .autoSize()
      .text(labelText, cfg.text, cfg.fontSize, TextLabel.Alignment.center)
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
  import yguilib.internal.uisystem_impl : UiSystemImpl;
  import yguilib.widget.layout_components : SizingMode;

  auto ui = new UiSystemImpl(null);
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
import yguilib.uisystem : UiRegistry, UiSystem;
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
  ui.widgetViews.register(view.getWidgetViewName(), view);
  ui.widgetViewControllers.register(ctrl.getControllerName(), ctrl);
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

  /// Builds the composite widget. parent and registry may be null in tests.
  Widget build(
    UiSystem ui,
    Widget parent,
    RectF rect,
    UiRegistry registry = null
  ) {
    assert(ui !is null, "ui must not be null");
    if (registry is null) {
      registry = ui;
    }
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
      .flexRow(8.0f, JustifyContent.center, AlignItems.center)
      .roundBackground(cfg.bg, cfg.cornerRadius)
      .border(cfg.border, 1.0f)
      .view(registry, renameMap, __CAMEL__WidgetViewName)
      .build();

    WidgetBuilder.make(ui)
      .parent(root)
      .name(rootName ~ "Btn")
      .rect(RectF(0, 0, cfg.width, cfg.height))
      .autoSize()
      .text(rootName, cfg.text, cfg.fontSize, TextLabel.Alignment.center)
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
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
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

  this(string actionEvent = null) {
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

    auto w = WidgetBuilder.make(ui)
      .parent(parent)
      .name(rootName)
      .rect(rect)
      .fixedSize(cfg.width, cfg.height)
      .padding(6, 12)
      .roundBackground(cfg.bg, cfg.cornerRadius)
      .border(cfg.border, 1.0f)
      .text(labelText, cfg.text, cfg.fontSize, TextLabel.Alignment.center)
      .component(new __NAME__Component(actionEvent))
      .build();
    w.inputEnabled = true;
    return w;
  }

private:
  __NAME__Style cfg;
  string widgetName = null;
  string labelText = "__NAME__";
  string actionEvent = "__CAMEL__Action";
}

/// WidgetSystem processing visible widgets with __NAME__Component.
final class __NAME__System : WidgetSystem {
  this(int priority = defaultPriority) nothrow @safe {
    super(priority);
  }

  override @property SystemPhase phases() const nothrow @safe {
    return SystemPhase.event | SystemPhase.preLayout;
  }

  override SystemEventResult handleEvent(
    in AppEvent event,
    ref WidgetSystemContext ctx
  ) {
    return SystemEventResult(false, false, timeoutMs);
  }
}

unittest {
  import yguilib.internal.uisystem_impl : UiSystemImpl;

  auto ui = new UiSystemImpl(null);
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
