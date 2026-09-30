# Invalidation Alternatives for Widget Component Mutations

This document analyzes alternatives to manually calling `markDirty()` when
changing component values on a `Widget` in `yguilib`.

---

## 1. Problem Statement

In `yguilib`, widgets own a collection of components (`WidgetComponents`) such
as `Background`, `TextLabel`, `Border`, and `FlexContainer`. Modifying fields
currently relies on manual invalidation:

```d
alphaWidget.components.background.color.a = newAlpha;
alphaWidget.markDirty(false); // easy to forget or misclassify
```

### Key Limitations
1. **Silent Stale UI**: Forgetting `markDirty()` leaves UI stale without errors.
2. **Leaky Granularity**: Callers must know whether a change requires layout
   recalculation (`markDirty(true)`) or paint redraw only (`markDirty(false)`).
3. **No Redundancy Filtering**: Callers repeatedly dirty widgets unless they
   manually guard every assignment with `if (val != newVal)`.
4. **Intermediate Invalidation**: Mutating multiple properties triggers
   repeated ancestor tree walks unless manually deferred.

---

## 2. Alternatives Overview

### Approach 1: Owner Back-Reference + Property Setters (@property)
Components maintain a `package(yguilib) Widget owner` reference populated when
attached to `WidgetComponents`. Modifiable fields use `@property` setters.

```d
class Background : Component {
  private ColorF _color;

  @property ColorF color() const { return _color; }
  @property void color(ColorF c) {
    if (_color == c) return;
    _color = c;
    if (owner !is null) owner.markDirty(false);
  }
}
```

* Each component dictates its invalidation kind (`paint` vs `layout`).
* D mixin templates can automate getter/setter generation:
  `mixin DirtyProperty!(ColorF, "color", InvalidationKind.paint);`

### Approach 2: Scoped & Batch Mutators on Widget
Components remain passive data objects without back-pointers. Modifications pass
through `Widget` methods:

```d
// Scoped mutator for a single component
w.modify!Background((bg) {
  bg.color = newColor;
}); // Automatically calls markDirty(false)

// Batch mutator for multi-property updates
w.batchUpdate({
  w.components.textLabel.caption = "Updated";
  w.components.textLabel.fontSize = 18.0f;
  w.components.background.color = newColor;
}); // Single markDirty(true) at the end of block
```

* Keeps components decoupled from widgets.
* Opens the door to converting small components (`Background`, `Border`) from
  heap-allocated classes to value `struct`s.

### Approach 3: Reactive / Signal Data Binding
Views bind component properties directly to observable model values:

```d
w.bindCaption(model.statusText);
w.bindAlpha(model.alphaValue);
```

* When model state changes, bindings push values and dirty flags automatically.
* Eliminates imperative `update()` polling in view classes.

---

## 3. Performance & Memory Overhead Evaluation

Evaluated on 64-bit architecture with D runtime (LDC / DMD).

```
+------------------------------------------------------------------------+
|                               MEMORY                                   |
+--------------------------+-----------------------+---------------------+
| Approach                 | Per Component         | Per Widget          |
+--------------------------+-----------------------+---------------------+
| Baseline (Manual)        | Base class (16B hdr)  | Base (96B comp ptr) |
| 1. Owner Back-Ref        | +8B (Widget owner)*   | 0B                  |
| 2. Scoped (Class)        | 0B                    | 0B                  |
| 2. Scoped (Struct)       | -16B+ (No class hdr)  | 0B (flat storage)   |
| 3. Reactive Bindings     | +32B..80B per binding | +16B (binding list) |
+--------------------------+-----------------------+---------------------+
*Often fits in existing 16-byte GC bucket padding with zero net increase.

+------------------------------------------------------------------------+
|                             PERFORMANCE                                |
+--------------------------+---------------------+-----------------------+
| Approach                 | Mutation Cost       | Multi-Field Batching  |
+--------------------------+---------------------+-----------------------+
| Baseline (Manual)        | ~1 cycle            | Manual markDirty      |
| 1. Owner Back-Ref        | ~2-4 cycles (inline)| Short-circuited check |
| 2. Scoped Mutator        | ~2-5 cycles         | Single markDirty pass |
| 3. Reactive Bindings     | ~15-30 cycles       | Queued / coalesced    |
+--------------------------+---------------------+-----------------------+
```

### Detailed Evaluation

#### 1. Owner Back-Reference + Properties
* **Memory**: +8 bytes per component instance for the `owner` pointer. Because
  the D GC allocates in power-of-two / 16-byte buckets, many components absorb
  the extra pointer with zero net GC allocation growth.
* **CPU / Inlining**: When getters/setters are `final` or non-virtual, LDC
  inlines them completely into a comparison, store, and conditional mark.
* **Deduplication**: Automatic early return when `_val == val` saves cycles by
  preventing unnecessary tree traversal.
* **Trade-off**: Requires components to belong to at most one widget at a time
  (matching existing usage).

#### 2. Scoped & Batch Mutators
* **Memory**: Zero added bytes for classes. If converted to value `struct`s,
  saves 16-byte object headers per component and reduces GC allocations.
* **CPU / Inlining**: `scope void delegate(...)` passed to a template method is
  readily inlined. Batching guarantees that setting 5 properties only runs
  `markDirty` once instead of walking parent nodes multiple times.
* **Trade-off**: Slightly less concise syntax (`w.modify!T(...)` vs direct
  assignment).

#### 3. Reactive Bindings
* **Memory**: Highest overhead. Every binding allocates listener delegates
  (16 bytes) and subscription tracking nodes. Risk of memory retention if
  not unbound properly when widgets are destroyed.
* **CPU**: Higher mutation cost due to indirect delegate calls through listener
  lists (~15–30 cycles). However, eliminates frame-polling CPU overhead during
  idle frames where no model data changes.
* **Trade-off**: High architectural complexity; best suited for large-scale data
  flows rather than immediate widget styling.

---

## 4. Summary Matrix

| Metric | Baseline | 1. Owner Setters | 2. Scoped Mut | 3. Reactive |
| :--- | :--- | :--- | :--- | :--- |
| **Ergonomics** | Poor | Best (`c.x=y`) | Good (`modify`) | Declarative |
| **Safety** | Unsafe | Safe (auto) | Safe (scoped) | Safe (bound) |
| **Memory** | Base | Low (+8B) | Zero / Negative | High (+32B+) |
| **CPU Cost** | 1 cycle | 2-4 cycles | 2-5 cycles | 15-30 cycles |
| **Batching** | Manual | Short-circuit | Single pass | Coalesced |
| **Structs** | No | No | Yes | No |

---

## 5. Recommendation for yguilib

1. **Phase 1 (Immediate Ergonomics)**: Adopt **Approach 1**. Add `owner` to
   `Component`, set it in `WidgetComponents`, and implement `@property`
   setters with a `DirtyProperty` mixin. This transparently fixes caller bugs
   without altering existing call-site ergonomics.
2. **Phase 2 (Batching)**: Add `batchUpdate(scope void delegate())` to `Widget`
   to coalesce multiple property updates into a single invalidation pass.
3. **Phase 3 (Optimization)**: Consider transitioning leaf visual components
   (`Background`, `Border`, `Size`) to value `struct`s using **Approach 2**
   to minimize GC heap pressure.
