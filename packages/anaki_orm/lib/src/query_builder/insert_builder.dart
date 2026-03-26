import '../db.dart';
import 'row_adapter.dart';

/// Fluent builder for INSERT statements.
///
/// ```dart
/// final affected = await qb.insert()
///     .values({'name': 'Ana', 'email': 'ana@example.com'})
///     .run();
/// ```
class InsertBuilder<T> {
  final AnakiDb _db;
  final RowAdapter _adapter;
  final String _table;
  Map<String, dynamic>? _values;

  InsertBuilder(this._db, this._adapter, this._table);

  /// Sets the column values to insert from a map.
  InsertBuilder<T> values(Map<String, dynamic> vals) {
    _values = vals;
    return this;
  }

  /// Sets the column values from a typed entity using the adapter.
  ///
  /// Null values are excluded so that database defaults (e.g. SERIAL, DEFAULT)
  /// are applied automatically.
  InsertBuilder<T> entity(T obj) {
    final raw = _adapter.toJson<T>(obj);
    raw.removeWhere((_, v) => v == null);
    _values = raw;
    return this;
  }

  /// Builds the SQL and params without executing.
  (String sql, Map<String, dynamic> params) build() {
    if (_values == null || _values!.isEmpty) {
      throw ArgumentError(
        'InsertBuilder: no values provided. '
        'Call .values() or .entity() before .build().',
      );
    }

    final cols = _values!.keys.toList();
    final placeholders = cols.map((c) => '@$c').join(', ');
    final sql =
        'INSERT INTO $_table (${cols.join(', ')}) '
        'VALUES ($placeholders)';

    return (sql, Map<String, dynamic>.from(_values!));
  }

  /// Executes the INSERT and returns the number of affected rows.
  Future<int> run() async {
    final (sql, params) = build();
    return _db.execute(sql, params);
  }
}
