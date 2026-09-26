# Video Editor Scrubbing Controls: Interaction Design Guide

This document details the standard interaction paradigms, input mappings, and performance considerations for implementing interactive scrubbing (interactive seek, fast forward, and rewind) across mouse and keyboard interfaces in desktop and web-based video editing applications (NLEs).

---

## 1. Mouse & Pointer Interactions

Mouse interactions generally balance rapid macro navigation with frame-accurate micro adjustments.

### 1.1 Playhead Dragging (Absolute Seeking)
* **Mechanic:** The user clicks and drags the playhead along the timeline ruler.
* **Coordinate Mapping:** Horizontal pixel offsets map directly to temporal positions based on the current zoom factor ($t = t_{\text{origin}} + \Delta x \times \text{scale}$).
* **User Feedback:** Cursor switches to an east-west resize or grab handle; hovering highlights the playhead bead.

### 1.2 Skimming / Hover Scrubbing
* **Mechanic:** Moving the pointer over a clip in the media pool, bin, or timeline scrubs the frame without requiring a click or drag.
* **Behavior:** Popularized by Final Cut Pro and modern video preview widgets (e.g., YouTube timeline hover). Moving the mouse out of the region restores the playhead to its previous parked position, whereas clicking locks the playhead to the current skimmed frame.

### 1.3 Relative Dragging (Scrubby Sliders & Pointer Lock)
* **Mechanic:** Clicking and dragging horizontally across a timecode label, viewer window, or mini-scrubber.
* **Implementation:** The browser/OS cursor is locked in place (`Pointer Lock API`), hidden, and horizontal motion deltas ($\Delta x$) continuously adjust the timestamp. This removes physical screen boundary constraints.

### 1.4 Variable-Gear Vertical Scrubbing (Fine Seeking)
* **Mechanic:** While dragging horizontally on a scrub bar, dragging the mouse vertically away from the baseline changes the gear ratio.
* **Gear Ratios:**
  * **Near baseline ($0$–$20\,\text{px}$):** $1\times$ speed (standard scale).
  * **Intermediate ($20$–$60\,\text{px}$):** $0.5\times$ or $0.25\times$ speed.
  * **Far ($> 60\,\text{px}$):** Frame-by-frame precision.

### 1.5 Wheel & Trackpad Inputs
* **Horizontal Scroll:** Pans the visible timeline window.
* **Modifier + Scroll (e.g., `Shift` + Wheel):** Steps the playhead incrementally along the timeline.
* **Pinch-to-Zoom / `Cmd`/`Ctrl` + Wheel:** Zooms centered on the playhead or cursor position, altering the scrubbing resolution dynamically.

---

## 2. Keyboard Interactions

Keyboard controls represent the professional NLE standard for high-throughput, non-destructive editing workflows.

### 2.1 The Industry-Standard J-K-L Transport Shuttle

| Key Combination | Function | Description |
| :--- | :--- | :--- |
| **`L`** | Shuttle Forward | Starts playback at $1\times$. Consecutive presses double speed ($2\times \to 4\times \to 8\times \to 16\times \to 32\times$). |
| **`J`** | Shuttle Backward | Starts reverse playback at $-1\times$. Consecutive presses double reverse speed ($-2\times \to -4\times \to -8\times \dots$). |
| **`K`** | Pause / Stop | Immediately stops playback and parks on the active frame. |
| **`K` + `L` (Hold)** | Slow Forward | Plays forward at half speed ($0.5\times$) or steps single frames continuously while held. |
| **`K` + `J` (Hold)** | Slow Reverse | Plays in reverse at half speed ($-0.5\times$) or steps single frames backward continuously while held. |
| **Hold `K`, Tap `L`** | Step Forward 1 Frame | Advances playhead by exactly one frame ($+1$). |
| **Hold `K`, Tap `J`** | Step Backward 1 Frame | Rewinds playhead by exactly one frame ($-1$). |

### 2.2 Arrow Key Stepping
* **`Left Arrow` / `Right Arrow`:** Steps backward or forward by exactly 1 frame.
* **`Shift` + `Left Arrow` / `Right Arrow`:** Steps by a defined large frame delta (commonly $1\text{ second}$, $5\text{ frames}$, or $10\text{ frames}$).

### 2.3 Direct Numeric Entry
* Typing numbers (or tapping a shortcut to focus the timecode field) allows jump-to-time commands:
  * Absolute time: Entering `01121000` jumps to `01:12:10:00`.
  * Relative offset: Entering `+30` moves the playhead ahead 30 frames; entering `-100` rewinds by 1 second (in drop-frame timecode).

---

## 3. Critical UX & Technical Edge Cases

### 3.1 Audio Scrubbing (Tape-Head Simulation)
* **Digital Squeal Prevention:** If scrubbing exceeds $2\times$ or $3\times$ playback velocity, audio output should automatically mute or apply high-frequency low-pass filtering.
* **Resampling:** When moving slowly or stepping frame-by-frame, output brief sampled chunks ($10$–$40\,\text{ms}$) with an envelope fade-out to prevent harsh audio clipping and speaker popping.

### 3.2 Snapping Dynamics
* **Default Snap:** The playhead snaps magnetic boundaries (cuts, markers, in/out points).
* **Temporary Override:** Holding `Shift`, `Alt`, or a configurable modifier key during mouse drag should dynamically invert snapping behavior.

### 3.3 Decoding Optimization
* **GOP (Group of Pictures) Bottlenecks:** Seeking non-intra video formats (e.g., standard H.264/H.265 long-GOP) backwards or at high speed requires decoding every preceding I-frame and P/B-frame up to the target, causing UI lag.
* **Mitigation:**
  * Render lower-resolution intra-frame scrub proxies (e.g., ProRes Proxy, DNxHR, or low-res WebM).
  * During high-speed drag or fast shuttling, skip intermediate frames and decode only keyframes (I-frames) until drag ends.