/**
 * guidemoapp.d - Interactive GUI feature showcase and testbed for yguilib.
 *
 * PURPOSE:
 * This optional demo application serves as a visual verification tool and
 * interactive playground to test new GUI features as they are implemented
 * in yguilib (and eventually yvidtrim, such as video playback components).
 *
 * CURRENT FEATURE COVERAGE:
 * 1. widget_painter.d & drawing_components.d:
 *    - Background styles: Style.rect, Style.round, Style.none.
 *    - Border styles: Style.rect, Style.dashed, Style.round, Style.roundDashed,
 *      and Style.none.
 *    - TextLabel: text rendering, custom colors, auto-measurement.
 *    - TextLabel options: multiline wrapping, explicit newlines, overflow
 *      ellipsis, horizontal alignment (left, center, right), live playground.
 *    - Alpha transparency: animated alpha blending.
 *    - Clipping: Widget.clipChildren and Widget.clipContents scissoring.
 *    - Visibility culling: toggling Widget.visible dynamically.
 * 2. layout_system.d (and flex/anchor/dimension subsystems):
 *    - SizingMode: fixed, auto_ (content-driven), and fraction (flex-grow).
 *    - Size bounds: minWidth, maxWidth, minHeight, maxHeight constraints.
 *    - Insets: Size.padding (inner) and Size.margin (outer clearance).
 *    - FlexContainer: FlexDirection (row, column), gap spacing.
 *    - JustifyContent: start, end, center, spaceBetween.
 *    - AlignItems: start, end, center, stretch.
 *    - Anchor: out-of-flow pinning (top, bottom, left, right) relative to
 *      parent bounds, including out-of-flow anchors inside flex containers.
 *
 * MAINTENANCE NOTE:
 * When adding new layout modes, drawing primitives, widgets, or components
 * to yguilib or yvidtrim (e.g. video rendering surfaces, timeline scrubbers),
 * update this demo with dedicated visual sections and interactive controls.
 *
 * KEYBOARD CONTROLS:
 *   [Tab]/[1]/[2] Switch demo page (Page 1: Layout, Page 2: TextLabel)
 *   [M]           Toggle multiline on interactive TextLabel
 *   [E]           Toggle overflow ellipsis on interactive TextLabel
 *   [L]           Cycle horizontal alignment (left -> center -> right)
 *   [D]           Toggle FlexDirection (row <-> column)
 *   [J]           Cycle JustifyContent (start -> end -> center -> spaceBetween)
 *   [A]           Cycle AlignItems (stretch -> start -> end -> center)
 *   [G]           Cycle flex gap (0, 8, 16, 24 px)
 *   [V]           Toggle child widget visibility (demonstrates flex re-flow)
 *   [T]           Cycle text sample (auto-sizing / playground caption)
 *   [Q]/[Esc]     Quit demo
 */
module guidemo.guidemoapp;

import yguilib.app : App;
import yguilib.window : Window;

import guidemo.controller : DemoController;

void main() {
  auto window = new Window(1280, 720, "yguilib feature demo - guidemo");
  auto app = new App(window);
  app.run(new DemoController(app));
}
