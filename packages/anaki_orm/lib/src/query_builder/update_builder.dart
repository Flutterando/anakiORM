import '../db.dart';
import 'row_adapter.dart';

/// Fluent builder for UPDATE statements.
///
/// ```dart
/// final affected = await qb.update()
///     .set({'email': 'new@example.com'})
///     .where('id = @id', {'id': 1})
///     .run();
/// ```
class UpdateBuilder {
  final AnakiDb _db;
  final RowAdapter _adapter;
  final String _table;

  final Map<String, dynamic> _setValues = {};
  final List<String> _whereClauses = [];
  final Map<String, dynamic> _params = {};

  UpdateBuilder(this._db, this._adapter, this._table);

  /// Sets the columns and values to update.
  UpdateBuilder set(Map<String, dynamic> values) {
    _setValues.addAll(values);
    return this;
  }

  /// Sets the columns and values from a typed entity using the adapter.
  ///
  /// Null values are excluded so that only provided fields are updated.
  UpdateBuilder setEntity<T>(T obj) {
    final raw = _adapter.toJson<T>(obj);
    raw.removeWhere((_, v) => v == null);
    _setValues.addAll(raw);
    return this;
  }

  /// Adds a WHERE clause.
  UpdateBuilder where(String clause, [Map<String, dynamic>? params]) {
    _whereClauses.add(clause);
    if (params != null) _params.addAll(params);
    return this;
  }

  /// Builds the SQL and params without executing.
  (String sql, Map<String, dynamic> params) build() {
    if (_setValues.isEmpty) {
      throw ArgumentError(
        'UpdateBuilder: no values provided. '
        'Call .set() before .build().',
      );
    }

    final setClauses = _setValues.keys.map((k) => '$k = @$k').join(', ');
    final buffer = StringBuffer('UPDATE $_table SET $setClauses');

    if (_whereClauses.isNotEmpty) {
      buffer.write(' WHERE ${_whereClauses.join(' AND ')}');
    }

    final allParams = <String, dynamic>{..._setValues, ..._params};
    return (buffer.toString(), allParams);
  }

  /// Executes the UPDATE and returns the number of affected rows.
  Future<int> run() async {
    final (sql, params) = build();
    return _db.execute(sql, params);
  }
}
