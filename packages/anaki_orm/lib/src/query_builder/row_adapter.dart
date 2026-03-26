/// Adapter that converts between `Map<String, dynamic>` and typed objects.
///
/// The generic `T` is resolved at the call site, allowing a single global
/// instance to handle all types.
///
/// In Vaden, this maps directly to DSON:
/// ```dart
/// @Bean()
/// RowAdapter rowAdapter(DSON dson) => RowAdapter(dson.fromJson, dson.toJson);
/// ```
class RowAdapter {
  /// Converts a database row map into a typed object `T`.
  final T Function<T>(Map<String, dynamic> row) fromJson;

  /// Converts a typed object `T` into a database row map.
  final Map<String, dynamic> Function<T>(T entity) toJson;

  /// Creates a [RowAdapter] with the given conversion functions.
  RowAdapter(this.fromJson, this.toJson);
}
