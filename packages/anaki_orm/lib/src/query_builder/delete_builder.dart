import '../db.dart';

/// Fluent builder for DELETE statements.
///
/// ```dart
/// final affected = await qb.delete()
///     .where('id = @id', {'id': 1})
///     .run();
/// ```
class DeleteBuilder {
  final AnakiDb _db;
  final String _table;

  final List<String> _whereClauses = [];
  final Map<String, dynamic> _params = {};

  DeleteBuilder(this._db, this._table);

  /// Adds a WHERE clause.
  DeleteBuilder where(String clause, [Map<String, dynamic>? params]) {
    _whereClauses.add(clause);
    if (params != null) _params.addAll(params);
    return this;
  }

  /// Builds the SQL and params without executing.
  (String sql, Map<String, dynamic> params) build() {
    final buffer = StringBuffer('DELETE FROM $_table');

    if (_whereClauses.isNotEmpty) {
      buffer.write(' WHERE ${_whereClauses.join(' AND ')}');
    }

    return (buffer.toString(), Map<String, dynamic>.from(_params));
  }

  /// Executes the DELETE and returns the number of affected rows.
  Future<int> run() async {
    final (sql, params) = build();
    return _db.execute(sql, params);
  }
}
