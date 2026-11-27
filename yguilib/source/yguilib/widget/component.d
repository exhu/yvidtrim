module yguilib.widget.component;

abstract class WidgetComponent {

}

/// Mixin providing `raw`, `fromRaw`, `alias raw this`, and size assertion for
/// packed `AppEvent.ViewData.value` unions in widget components.
mixin template AppEventViewValueMixin() {
  import yguilib.events : AppEvent;

  /// Raw 64-bit integer array stored in `AppEvent.ViewData.value`.
  ulong[AppEvent.ViewData.valueSize] raw;

  static assert(
    typeof(this).sizeof == (ulong[AppEvent.ViewData.valueSize]).sizeof
  );

  /// Allows implicit conversion to array for `ViewAppEventBuilder.value`.
  alias raw this;

  /// Constructs from raw array payload.
  static typeof(this) fromRaw(
    in ulong[AppEvent.ViewData.valueSize] raw
  ) {
    typeof(this) val;
    val.raw = raw;
    return val;
  }
}
