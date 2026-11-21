# Virtual List Architecture & Implementation in D (Flex Layout Engine)

## Executive Summary

When building a scrollable list widget over a massive, dynamically paged dataset with variable row heights (such as a chat application or log viewer), instantiating widgets for the entire dataset will exhaust memory and CPU. The standard solution used by modern UI toolkits (Android's `RecyclerView`, Flutter's `SliverList`) is a **Virtual (Recycled) List** using **Anchor-Based Positioning** and a **Pull-Based Data Adapter**.

### Key Architectural Takeaways
1. **Avoid Asynchronous Layout Events:** Do not emit events during layout that ask external code to populate widgets and re-trigger layout. In a flex layout engine, mutating the widget tree via events during or immediately after a layout pass causes frame-delayed flickering, layout thrashing, and infinite loops (e.g., adding a row triggers a scrollbar, narrowing the viewport, wrapping text, and changing row heights again).
2. **Synchronous Pull-Based Binding:** The `VirtualList` container must take direct control of data binding and child measurement *inside* its own `arrange()` step via an `IVirtualAdapter` interface, while suppressing upward layout invalidation calls during binding.
3. **Anchor-Based Viewport State:** Never rely on an absolute pixel `scrollY` from the top of the document when item heights are unknown or paged in asynchronously. Instead, track an `anchorIndex` (index of the top-most visible item) and `anchorOffset` (pixel offset of that item's top edge relative to the viewport).
4. **Zero-Allocation Recycling:** Maintain a pool of off-screen widgets keyed by item template type (`Widget[][int] freePools`) and use D's `assumeSafeAppend()` to achieve zero GC allocations per frame at 120Hz.

---

## 1. Core Architecture: Anchor-Based Positioning

When items have unknown, variable heights and data arrives in pages, an absolute pixel offset (e.g., `scrollY = 45000px`) fails whenever items above the viewport load or resize, causing visible content to jump violently.

Instead, define the viewport state around an **Anchor Item**:
* **`anchorIndex` (`size_t`)**: The index in your dataset of the top-most visible item.
* **`anchorOffset` (`float`)**: The pixel offset of that anchor item's top edge relative to the viewport's top edge (typically $\le 0$ when partially scrolled off-screen).

All other visible widgets are positioned strictly relative to this anchor during the layout pass.

### Single-Pass Virtual Layout Algorithm

During the parent layout pass, `VirtualList` receives its available `(width, height)` and runs the following synchronous steps inside `arrange()`:

1. **Detect Width Changes:** If `width != lastMeasuredWidth`, clear the height cache because flex children (such as wrapped text) will reflow and change height.
2. **Apply Scroll Delta:** Add `pendingScrollDelta` to `anchorOffset` and reset `pendingScrollDelta = 0`.
3. **Advance or Rewind the Anchor:**
   * If `anchorOffset + anchorHeight <= 0`, advance `anchorIndex++` and add `anchorHeight` to `anchorOffset` until the anchor item intersects the top edge.
   * If `anchorOffset > 0` (scrolling up exposed space above the anchor), decrement `anchorIndex--`, measure the previous item, and subtract its height from `anchorOffset`.
4. **Fill Downwards:** Starting at `currIdx = anchorIndex` and `currY = anchorOffset`, acquire widgets from the active list or `freePools`, bind data, run flex measurement (`exactWidth = viewportWidth`, `maxHeight = infinity`), and place each widget at `currY` until `currY >= height + overscanPixels` or the dataset ends.
5. **Resolve Bottom Underflow:** If the end of the dataset is reached and `currY < height`, shift all visible items down so the last item touches the bottom edge, and backfill newly exposed space at the top.
6. **Fill Top Overscan & Recycle:** Populate the top overscan buffer above `anchorIndex`, then move any unclaimed widgets from the previous frame into `freePools` (skipping focused widgets so active user input is never destroyed).

---

## 2. Handling Edge Cases in Flex Engines

| Challenge | Solution |
| :--- | :--- |
| **Scrollbar Thumb Jumping** | Maintain a running sum of all values in `heightCache` (`knownHeightsSum`). Estimate total content height as `knownHeightsSum + (unmeasuredCount * avgHeight)`. Interpolate within the current anchor item using its actual cached height so scrolling across a tall item is strictly monotonic. |
| **Width Resize Invalidation** | In a flex layout, changing the `VirtualList` width changes text wrapping inside rows. When `viewportWidth != lastMeasuredWidth`, clear `heightCache`, keep `anchorIndex` fixed, and re-measure visible items. |
| **Async Page Arrival** | When `requestPrefetch` finishes loading a page asynchronously from disk or network, call `virtualList.notifyDataInserted(index, count)`. If `index <= anchorIndex`, increment `anchorIndex += count` so the visible screen does not move a single pixel. |
| **Fast Kinetic Flicks Across Unloaded Pages** | If a user flicks at high velocity across dozens of items in a single frame, skip binding and flex-measuring intermediate off-screen items when `abs(anchorOffset) > height * 2.0f` by stepping over them with `getAverageItemHeight()`. |
| **Focus & Active Input State** | If a row contains an interactive widget holding keyboard/input focus (`widget.isFocused`), park it off-screen (`y = -99999.0f`) rather than pushing it into `freePools`. |

---

## 3. Complete D Implementation

The following module combines the base interfaces, the `VirtualList` layout/recycling loop, hybrid scrollbar thumb dragging (`scrollToRatio`), and smooth frame-rate-independent wheel/kinetic scrolling (`onTick`).

```d
module gui.virtuallist;

import std.algorithm : swap, remove, max, min, clamp;
import std.math : isNaN, abs, exp;

/// Implemented by the application data source
interface IVirtualAdapter {
    /// Total known items (or currently loaded items)
    size_t itemCount();

    /// Returns a template ID (0 if all rows share the same widget structure)
    int getItemType(size_t index);

    /// Allocates a new widget tree for a given template ID
    Widget createWidget(int itemType);

    /// Populates a recycled widget with data for `index`.
    /// Guarded by VirtualList so child mutations do not bubble layout invalidation.
    void updateWidget(Widget widget, size_t index);

    /// Called when the layout pass gets within N items of the edge of loaded data
    void requestPrefetch(size_t startIndex, size_t count);
}

/// Normalized metrics for rendering an external or overlay scrollbar
struct ScrollbarState {
    float thumbSizeRatio;     // 0.0 .. 1.0 (e.g., 0.1 = thumb is 10% of track height)
    float thumbPositionRatio; // 0.0 .. 1.0 (0.0 = top, 1.0 = bottom)
}

/// Assumed base Widget API in your Flex GUI library
abstract class Widget {
    float x = 0.0f, y = 0.0f, width = 0.0f, height = 0.0f;
    bool isFocused = false;

    /// Measures widget given width/height constraints. Sets this.width and this.height.
    abstract void measure(float availableWidth, float availableHeight);

    /// Positions internal flex children inside (0, 0, this.width, this.height)
    abstract void arrange();

    /// Requests parent to re-run layout
    void invalidateLayout() {
        // In your GUI library, this bubbles up to the root window
    }

    /// Requests the main event loop to call onTick(dt) on the next frame
    void requestAnimationFrame() {
        // Hook into your GUI library's animation ticker
    }
}

/// Virtualized, variable-height scrollable list container
class VirtualList : Widget {
    private struct ActiveItem {
        size_t index;
        int itemType;
        Widget widget;
        float y = 0.0f;
        float height = 0.0f;
    }

    private {
        IVirtualAdapter adapter;
        ActiveItem[] activeItems;        // Sorted by index ascending
        Widget[][int] freePools;         // Recycled off-screen widgets by itemType

        // Viewport & Anchor State
        size_t anchorIndex = 0;
        float anchorOffset = 0.0f;       // Y position of anchorIndex relative to top (<= 0)
        float pendingScrollDelta = 0.0f; // Accumulated scroll wheel / drag delta
        float lastMeasuredWidth = -1.0f;
        float overscanPixels = 120.0f;   // Extra buffer above/below viewport

        // Height Cache & Scrollbar Estimation
        float[size_t] heightCache;
        double knownHeightsSum = 0.0;
        bool isPerformingLayout = false;

        // Smooth Mouse Wheel State
        float remainingWheelDelta = 0.0f;
        float wheelSmoothness = 18.0f;   // Higher = snappier wheel response

        // Touch / Flick Inertia State
        float velocityY = 0.0f;          // Pixels per second
        float decelerationRate = 4.5f;   // Exponential friction coefficient
        bool isDraggingContent = false;
    }

    this(IVirtualAdapter adapter) {
        this.adapter = adapter;
    }

    // =========================================================================
    // Public Scrolling & Data Notification API
    // =========================================================================

    /// Immediate pixel scroll delta.
    /// Negative delta = scroll down (content moves up)
    /// Positive delta = scroll up (content moves down)
    void scrollBy(float deltaY) {
        if (deltaY == 0.0f) return;
        pendingScrollDelta += deltaY;
        invalidateLayout();
    }

    /// Call when an async page finishes loading before or after current items
    void notifyDataInserted(size_t insertIndex, size_t count) {
        if (insertIndex <= anchorIndex && adapter.itemCount() > count) {
            anchorIndex += count; // Keep current visible items stationary
        }
        invalidateLayout();
    }

    /// Call on discrete mouse wheel events (e.g. steps = -1 for down, +1 for up)
    void onMouseWheel(float steps, float pixelsPerStep = 90.0f) {
        velocityY = 0.0f; // Cancel flick inertia if wheel is used
        remainingWheelDelta += steps * pixelsPerStep;
        requestAnimationFrame();
    }

    /// Call when user starts dragging content directly (touch or middle-click drag)
    void onContentDragStart() {
        stopKineticScroll();
        isDraggingContent = true;
    }

    /// Call on pointer move while dragging content
    void onContentDragMove(float deltaY, float dt) {
        if (dt > 0.0001f) {
            // Low-pass filter velocity (70% new instantaneous velocity, 30% previous)
            float instantVel = deltaY / dt;
            velocityY = (velocityY * 0.3f) + (instantVel * 0.7f);
        }
        scrollBy(deltaY);
    }

    /// Call when user releases content drag
    void onContentDragEnd() {
        isDraggingContent = false;
        if (abs(velocityY) > 40.0f) {
            requestAnimationFrame();
        } else {
            velocityY = 0.0f;
        }
    }

    /// Immediately halts any ongoing wheel or flick animation
    void stopKineticScroll() {
        remainingWheelDelta = 0.0f;
        velocityY = 0.0f;
    }

    /// Call once per frame from your GUI main loop while animations are active.
    /// Returns `true` if animation is still running, `false` when settled.
    bool onTick(float dt) {
        if (dt <= 0.0f || isDraggingContent) return false;
        dt = min(dt, 0.1f); // Clamp large frame spikes

        float frameDelta = 0.0f;

        // A. Process Smooth Wheel Interpolation (Frame-rate independent exponential easing)
        if (abs(remainingWheelDelta) > 0.5f) {
            float factor = 1.0f - exp(-wheelSmoothness * dt);
            float step = remainingWheelDelta * factor;
            frameDelta += step;
            remainingWheelDelta -= step;
        } else {
            remainingWheelDelta = 0.0f;
        }

        // B. Process Flick Inertia: v(t) = v0 * e^(-k * dt)
        if (abs(velocityY) > 5.0f) {
            float nextVelocity = velocityY * exp(-decelerationRate * dt);
            // Exact integral of velocity over dt: (v0 - v1) / k
            float step = (velocityY - nextVelocity) / decelerationRate;
            frameDelta += step;
            velocityY = nextVelocity;
        } else {
            velocityY = 0.0f;
        }

        // Apply combined movement
        if (abs(frameDelta) > 0.01f) {
            scrollBy(frameDelta);

            // Stop inertia immediately if we hit the top or bottom boundary
            if (isAtBoundary(frameDelta)) {
                stopKineticScroll();
                return false;
            }
            return true; // Keep ticking next frame
        }

        return false;
    }

    // =========================================================================
    // Scrollbar Metrics & Thumb Dragging
    // =========================================================================

    /// Compute stable scrollbar thumb metrics for rendering
    ScrollbarState getScrollbarState() const {
        const size_t total = adapter ? adapter.itemCount() : 0;
        if (total == 0 || height <= 0) return ScrollbarState(1.0f, 0.0f);

        const float avgH = getAverageItemHeight();
        const float estimatedTotalHeight = getEstimatedTotalHeight(total, avgH);

        if (estimatedTotalHeight <= height) {
            return ScrollbarState(1.0f, 0.0f); // Everything fits on screen
        }

        // Check if we are pinned to the very bottom
        if (activeItems.length > 0) {
            const auto last = activeItems[$ - 1];
            if (last.index == total - 1 && (last.y + last.height) <= height + 0.5f) {
                float ratio = clamp(height / estimatedTotalHeight, 0.05f, 1.0f);
                return ScrollbarState(ratio, 1.0f);
            }
        }

        // Use actual height of the anchor item so scrolling within a tall item is monotonic
        float anchorH = avgH;
        if (auto cached = anchorIndex in heightCache) anchorH = *cached;

        // Fractional progress through the current anchor item (0.0 at top edge, 1.0 at bottom edge)
        float anchorFraction = anchorH > 0 ? clamp(-anchorOffset / anchorH, 0.0f, 1.0f) : 0.0f;

        // Estimate how many items fit inside a single viewport
        float visibleItemCount = height / avgH;
        float maxScrollableItems = max(1.0f, cast(float)total - visibleItemCount);

        float posRatio = clamp((cast(float)anchorIndex + anchorFraction) / maxScrollableItems, 0.0f, 1.0f);
        float sizeRatio = clamp(height / estimatedTotalHeight, 0.05f, 1.0f);

        return ScrollbarState(sizeRatio, posRatio);
    }

    /// Call when user drags the scrollbar thumb to normalized position `t` in [0.0, 1.0]
    void scrollToRatio(float t) {
        if (adapter is null) return;
        const size_t total = adapter.itemCount();
        if (total == 0) return;

        stopKineticScroll();
        t = clamp(t, 0.0f, 1.0f);

        // Snap cleanly to the very first item
        if (t <= 0.0001f) {
            anchorIndex = 0;
            anchorOffset = 0.0f;
            pendingScrollDelta = 0.0f;
            invalidateLayout();
            return;
        }

        // Snap cleanly to the very last item
        if (t >= 0.9999f) {
            anchorIndex = total - 1;
            anchorOffset = 0.0f; // Step 7 (Bottom Underflow) in arrange() pulls it flush to the bottom
            pendingScrollDelta = 0.0f;
            invalidateLayout();
            return;
        }

        const float avgH = getAverageItemHeight();
        const float visibleItems = height / avgH;
        const float maxScrollableIndex = max(0.0f, cast(float)total - visibleItems);

        // Target fractional index (e.g. item 452.65)
        const float targetVirtualIndex = t * maxScrollableIndex;
        const size_t targetIdx = cast(size_t)targetVirtualIndex;
        const float remainderFraction = targetVirtualIndex - cast(float)targetIdx;

        // If jumping less than ~15 items away, use pixel delta so visible items glide smoothly
        ptrdiff_t indexDiff = cast(ptrdiff_t)targetIdx - cast(ptrdiff_t)anchorIndex;
        if (abs(indexDiff) <= 15) {
            float currentAnchorH = (anchorIndex in heightCache) ? heightCache[anchorIndex] : avgH;
            float currentVirtualIdx = cast(float)anchorIndex + (-anchorOffset / currentAnchorH);
            float deltaItems = currentVirtualIdx - targetVirtualIndex;
            scrollBy(deltaItems * avgH);
            return;
        }

        // Teleporting across a large range: set anchor directly
        anchorIndex = min(targetIdx, total - 1);
        float targetAnchorH = (anchorIndex in heightCache) ? heightCache[anchorIndex] : avgH;
        anchorOffset = -(remainderFraction * targetAnchorH);
        pendingScrollDelta = 0.0f;

        invalidateLayout();
    }

    // =========================================================================
    // Core Layout & Recycling Engine
    // =========================================================================

    override void invalidateLayout() {
        // Ignore child invalidations triggered during adapter.updateWidget()
        if (isPerformingLayout) return;
        super.invalidateLayout();
    }

    override void measure(float availableWidth, float availableHeight) {
        this.width = availableWidth;
        this.height = availableHeight;
    }

    override void arrange() {
        if (adapter is null || adapter.itemCount() == 0 || width <= 0 || height <= 0) {
            recycleAll();
            return;
        }

        isPerformingLayout = true;
        scope(exit) isPerformingLayout = false;

        const size_t totalItems = adapter.itemCount();

        // 1. Detect Width Change -> Invalidate Height Cache
        if (abs(width - lastMeasuredWidth) > 0.5f) {
            heightCache.clear();
            knownHeightsSum = 0.0;
            lastMeasuredWidth = width;
        }

        // 2. Clamp Anchor if dataset shrank
        if (anchorIndex >= totalItems) {
            anchorIndex = totalItems - 1;
            anchorOffset = 0.0f;
        }

        // 3. Apply Pending Scroll Delta
        anchorOffset += pendingScrollDelta;
        pendingScrollDelta = 0.0f;

        // 4. Advance Anchor Downwards if scrolled completely past the top edge
        while (anchorIndex < totalItems) {
            float h = measureOrGetActiveHeight(anchorIndex);
            if (anchorOffset + h <= 0.0f && anchorIndex + 1 < totalItems) {
                anchorOffset += h;
                anchorIndex++;
            } else {
                break;
            }
        }

        // 5. Walk Backwards if scrolling up exposed space above anchor (anchorOffset > 0)
        while (anchorOffset > 0.0f && anchorIndex > 0) {
            anchorIndex--;
            float h = measureOrGetActiveHeight(anchorIndex);
            anchorOffset -= h;
        }

        // Clamp top over-scroll (cannot scroll above item 0)
        if (anchorIndex == 0 && anchorOffset > 0.0f) {
            anchorOffset = 0.0f;
        }

        // 6. Primary Pass: Fill Downwards from (anchorIndex, anchorOffset)
        ActiveItem[] nextActive;
        size_t currIdx = anchorIndex;
        float currY = anchorOffset;

        while (currIdx < totalItems && currY < height + overscanPixels) {
            ActiveItem item = acquireAndMeasureItem(currIdx);
            item.y = currY;
            item.widget.y = currY;
            nextActive ~= item;

            currY += item.height;
            currIdx++;
        }

        // 7. Handle Bottom Underflow (Scrolled past the end of the list)
        if (currIdx == totalItems && currY < height) {
            float underflow = height - currY;
            foreach (ref item; nextActive) {
                item.y += underflow;
                item.widget.y = item.y;
            }
            anchorOffset += underflow;

            // Backfill top space opened up by shifting items down
            while (anchorOffset > -overscanPixels && anchorIndex > 0) {
                anchorIndex--;
                ActiveItem topItem = acquireAndMeasureItem(anchorIndex);
                anchorOffset -= topItem.height;
                topItem.y = anchorOffset;
                topItem.widget.y = anchorOffset;
                nextActive = topItem ~ nextActive;
            }

            // Re-clamp if entire dataset is shorter than viewport height
            if (anchorIndex == 0 && anchorOffset > 0.0f) {
                float shiftUp = anchorOffset;
                anchorOffset = 0.0f;
                foreach (ref item; nextActive) {
                    item.y -= shiftUp;
                    item.widget.y = item.y;
                }
            }
        }

        // 8. Fill Top Overscan Buffer (above anchorIndex)
        size_t overscanIdx = anchorIndex;
        float overscanY = anchorOffset;
        while (overscanIdx > 0 && overscanY > -overscanPixels) {
            overscanIdx--;
            ActiveItem item = acquireAndMeasureItem(overscanIdx);
            overscanY -= item.height;
            item.y = overscanY;
            item.widget.y = overscanY;
            nextActive = item ~ nextActive;
        }

        // 9. Recycle Unused Active Items
        recycleUnclaimedItems(nextActive);
        activeItems = nextActive;

        // 10. Trigger Page Prefetch if near the end of loaded data
        if (currIdx + 15 >= totalItems) {
            adapter.requestPrefetch(totalItems, 50);
        }
    }

    // =========================================================================
    // Internal Helpers
    // =========================================================================

    private ActiveItem acquireAndMeasureItem(size_t index) {
        int type = adapter.getItemType(index);

        // 1. Check if already in activeItems from the previous frame
        foreach (ref existing; activeItems) {
            if (existing.index == index && existing.itemType == type && existing.widget !is null) {
                Widget w = existing.widget;
                existing.widget = null; // Claim ownership so step 9 doesn't recycle it

                // Re-measure only if width changed or height wasn't cached
                if ((index in heightCache) is null) {
                    w.measure(width, float.infinity);
                    w.arrange();
                    updateHeightCache(index, w.height);
                }
                return ActiveItem(index, type, w, 0.0f, w.height);
            }
        }

        // 2. Pull from freePool or allocate a new widget
        Widget w = null;
        if (auto pool = type in freePools) {
            if ((*pool).length > 0) {
                w = (*pool)[$ - 1];
                (*pool).length -= 1;
                (*pool).assumeSafeAppend(); // Prevent reallocation on next push
            }
        }
        if (w is null) {
            w = adapter.createWidget(type);
        }

        // 3. Bind Data & Run Flex Layout
        adapter.updateWidget(w, index);
        w.x = 0.0f;
        w.measure(width, float.infinity); // Exact width, unconstrained height
        w.arrange();

        updateHeightCache(index, w.height);
        return ActiveItem(index, type, w, 0.0f, w.height);
    }

    private float measureOrGetActiveHeight(size_t index) {
        // 1. Always use exact cached height if we already visited this row
        if (auto cached = index in heightCache) {
            return *cached;
        }

        // 2. Fast-forward optimization: if anchorOffset is > 2 viewports away from 0,
        // avoid instantiating and measuring off-screen intermediate rows during fast flicks.
        if (abs(anchorOffset) > height * 2.0f) {
            return getAverageItemHeight();
        }

        // 3. Near the viewport: actually bind & measure the widget
        ActiveItem temp = acquireAndMeasureItem(index);
        activeItems ~= temp;
        return temp.height;
    }

    private void updateHeightCache(size_t index, float h) {
        if (auto old = index in heightCache) {
            knownHeightsSum -= *old;
        }
        heightCache[index] = h;
        knownHeightsSum += h;
    }

    private void recycleUnclaimedItems(ref ActiveItem[] nextActive) {
        foreach (ref oldItem; activeItems) {
            if (oldItem.widget is null) continue; // Already claimed by nextActive

            // Never recycle a widget that currently holds keyboard/input focus
            if (oldItem.widget.isFocused) {
                oldItem.y = -99999.0f; // Park off-screen
                oldItem.widget.y = oldItem.y;
                nextActive ~= oldItem;
                continue;
            }

            freePools[oldItem.itemType] ~= oldItem.widget;
            oldItem.widget = null;
        }
    }

    private void recycleAll() {
        foreach (ref item; activeItems) {
            if (item.widget !is null) {
                freePools[item.itemType] ~= item.widget;
            }
        }
        activeItems.length = 0;
        activeItems.assumeSafeAppend();
    }

    private float getAverageItemHeight() const {
        return heightCache.length > 0
            ? cast(float)(knownHeightsSum / heightCache.length)
            : 44.0f;
    }

    private float getEstimatedTotalHeight(size_t total, float avgH) const {
        size_t unmeasured = total > heightCache.length ? total - heightCache.length : 0;
        return cast(float)knownHeightsSum + (unmeasured * avgH);
    }

    private bool isAtBoundary(float attemptedDelta) const {
        if (adapter is null || adapter.itemCount() == 0) return true;

        // Scrolling up (content moving down, attemptedDelta > 0) and already at top
        if (attemptedDelta > 0 && anchorIndex == 0 && anchorOffset >= -0.01f) {
            return true;
        }

        // Scrolling down (attemptedDelta < 0) and last item is already flush with bottom
        if (attemptedDelta < 0 && activeItems.length > 0) {
            const auto last = activeItems[$ - 1];
            if (last.index + 1 == adapter.itemCount() && (last.y + last.height) <= height + 0.5f) {
                return true;
            }
        }
        return false;
    }
}
```