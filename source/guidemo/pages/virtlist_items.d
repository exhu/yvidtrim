/**
 * virtlist_items.d - Page 7 item data models for the vertical media browser
 * and horizontal filmstrip VirtLists.
 */
module guidemo.pages.virtlist_items;

import yguilib.model : VersionedModel;

/// Row kinds rendered by the single reusable template in VerticalMediaProvider.
enum VerticalItemKind : ubyte {
  header,
  video,
  image,
  file,
}

/// Logical metadata for one item in the vertical media & file browser list.
struct VerticalItemData {
  VerticalItemKind kind;
  bool expanded = false;
  uint itemId = 0;
}

/// Card kinds rendered by HorizontalStripProvider.
enum HorizontalItemKind : ubyte {
  keyframe,
  segment,
  marker,
}

/// Logical metadata for one item in the horizontal filmstrip list.
struct HorizontalItemData {
  HorizontalItemKind kind;
  bool resized = false;
  uint itemId = 0;
}

/**
 * Item data for the vertical media & file browser VirtList. Mutating
 * methods must be called between `ModelTracker.edit()` and `commit()`.
 */
final class VerticalItemsModel : VersionedModel {
  VerticalItemData[] items;
  uint nextItemId = 0;
  /// Incremented by `resetItems` so providers can drop per-row state.
  size_t resetGeneration = 0;

  /// Returns the number of items.
  size_t itemsLength() const {
    return items.length;
  }

  /// Toggles expanded state on an expanded visible item, or first visible
  /// video row, or `firstVis`. Returns the modified index or `size_t.max`.
  size_t toggleExpandNear(size_t firstVis, size_t visCount) {
    if (items.length == 0) {
      return size_t.max;
    }
    const size_t start = (firstVis < items.length)
      ? firstVis
      : items.length - 1;
    const size_t end = (start + visCount <= items.length)
      ? (start + visCount)
      : items.length;
    foreach (i; start .. end) {
      if (items[i].expanded) {
        items[i].expanded = false;
        return i;
      }
    }
    foreach (i; start .. end) {
      if (items[i].kind == VerticalItemKind.video) {
        items[i].expanded = true;
        return i;
      }
    }
    items[start].expanded = !items[start].expanded;
    return start;
  }

  /// Inserts a video item at `idx` (clamped to the end).
  void insertItemAt(size_t idx) {
    import std.algorithm.comparison : min;
    const size_t clamped = min(idx, items.length);
    const auto inserted = VerticalItemData(
      VerticalItemKind.video, false, nextItemId++
    );
    items = items[0 .. clamped] ~ inserted ~ items[clamped .. $];
  }

  /// Removes the item at `idx`; out-of-range is ignored.
  void removeItemAt(size_t idx) {
    if (idx >= items.length) {
      return;
    }
    items = items[0 .. idx] ~ items[idx + 1 .. $];
  }

  /// Replaces items with `count` generated items.
  void resetItems(size_t count) {
    items.length = count;
    foreach (i; 0 .. count) {
      items[i] = VerticalItemData(kindForIndex(i), false, cast(uint) i);
    }
    nextItemId = cast(uint) count;
    resetGeneration += 1;
  }

private:
  static VerticalItemKind kindForIndex(size_t idx) {
    if (idx % 12 == 0) {
      return VerticalItemKind.header;
    }
    if (idx % 4 == 1) {
      return VerticalItemKind.video;
    }
    if (idx % 4 == 2) {
      return VerticalItemKind.image;
    }
    return VerticalItemKind.file;
  }
}

/**
 * Item data for the horizontal filmstrip VirtList. Mutating methods must be
 * called between `ModelTracker.edit()` and `commit()`.
 */
final class HorizontalItemsModel : VersionedModel {
  HorizontalItemData[] items;
  uint nextItemId = 0;

  /// Returns the number of items.
  size_t itemsLength() const {
    return items.length;
  }

  /// Toggles resized state on a resized visible card, or first visible
  /// segment, or `firstVis`. Returns the modified index or `size_t.max`.
  size_t toggleResizeNear(size_t firstVis, size_t visCount) {
    if (items.length == 0) {
      return size_t.max;
    }
    const size_t start = (firstVis < items.length)
      ? firstVis
      : items.length - 1;
    const size_t end = (start + visCount <= items.length)
      ? (start + visCount)
      : items.length;
    foreach (i; start .. end) {
      if (items[i].resized) {
        items[i].resized = false;
        return i;
      }
    }
    foreach (i; start .. end) {
      if (items[i].kind == HorizontalItemKind.segment) {
        items[i].resized = true;
        return i;
      }
    }
    items[start].resized = !items[start].resized;
    return start;
  }

  /// Inserts a segment item at `idx` (clamped to the end).
  void insertItemAt(size_t idx) {
    import std.algorithm.comparison : min;
    const size_t clamped = min(idx, items.length);
    const auto inserted = HorizontalItemData(
      HorizontalItemKind.segment, false, nextItemId++
    );
    items = items[0 .. clamped] ~ inserted ~ items[clamped .. $];
  }

  /// Removes the item at `idx`; out-of-range is ignored.
  void removeItemAt(size_t idx) {
    if (idx >= items.length) {
      return;
    }
    items = items[0 .. idx] ~ items[idx + 1 .. $];
  }

  /// Replaces items with `count` generated items.
  void resetItems(size_t count) {
    items.length = count;
    foreach (i; 0 .. count) {
      items[i] = HorizontalItemData(kindForIndex(i), false, cast(uint) i);
    }
    nextItemId = cast(uint) count;
  }

private:
  static HorizontalItemKind kindForIndex(size_t idx) {
    if (idx % 5 == 0) {
      return HorizontalItemKind.marker;
    }
    if (idx % 3 == 1) {
      return HorizontalItemKind.segment;
    }
    return HorizontalItemKind.keyframe;
  }
}

unittest {
  auto v = new VerticalItemsModel();
  v.resetItems(24);
  assert(v.itemsLength == 24);
  assert(v.items[0].kind == VerticalItemKind.header);
  assert(v.items[1].kind == VerticalItemKind.video);
  assert(v.resetGeneration == 1);

  v.insertItemAt(0);
  assert(v.itemsLength == 25);
  assert(v.items[0].kind == VerticalItemKind.video);
  assert(v.items[0].itemId == 24);
  v.removeItemAt(0);
  assert(v.items[0].kind == VerticalItemKind.header);
  v.removeItemAt(100);
  assert(v.itemsLength == 24);

  // First video in range gets expanded, then the expanded one collapses
  assert(v.toggleExpandNear(0, 4) == 1);
  assert(v.items[1].expanded);
  assert(v.toggleExpandNear(0, 4) == 1);
  assert(!v.items[1].expanded);

  auto h = new HorizontalItemsModel();
  h.resetItems(10);
  assert(h.items[0].kind == HorizontalItemKind.marker);
  assert(h.items[1].kind == HorizontalItemKind.segment);
  assert(h.toggleResizeNear(0, 3) == 1);
  assert(h.items[1].resized);
  h.insertItemAt(100);
  assert(h.itemsLength == 11);
  assert(h.items[10].kind == HorizontalItemKind.segment);
  h.removeItemAt(10);
  assert(h.itemsLength == 10);
  assert(new HorizontalItemsModel().toggleResizeNear(0, 1) == size_t.max);
}
