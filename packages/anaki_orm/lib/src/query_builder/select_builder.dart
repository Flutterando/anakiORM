import '../db.dart';
import '../driver.dart';
import '../paged_result.dart';
import 'row_adapter.dart';

/// Fluent builder for SELECT queries.
///
/// ```dart
/// final users = await qb.select()
///     .columns(['id', 'name'])
///     .where('active = @active', {'active': true})
///     .orderBy('name')
///     .list();
/// ```
class SelectBuilder<T> {
  final AnakiDb _db;
  final RowAdapter _adapter;
  final String _table;

  final List<String> _columns = [];
  final List<String> _whereClauses = [];
  final Map<String, dynamic> _params = {};
  final List<String> _orderByClauses = [];
  final List<String> _groupByClauses = [];
  final List<String> _havingClauses = [];
  final List<String> _joins = [];
  int? _limit;
  int? _offset;
  bool _distinct = false;

  SelectBuilder(this._db, this._adapter, this._table);

  /// Sets the columns to select. Defaults to `*` if not called.
  SelectBuilder<T> columns(List<String> cols) {
    _columns.addAll(cols);
    return this;
  }

  /// Adds a single column to select.
  SelectBuilder<T> column(String col) {
    _columns.add(col);
    return this;
  }

  /// Adds a WHERE clause (AND). Multiple calls are combined with AND.
  SelectBuilder<T> where(String clause, [Map<String, dynamic>? params]) {
    _whereClauses.add(clause);
    if (params != null) _params.addAll(params);
    return this;
  }

  /// Adds a WHERE clause combined with OR.
  SelectBuilder<T> orWhere(String clause, [Map<String, dynamic>? params]) {
    if (_whereClauses.isEmpty) {
      _whereClauses.add(clause);
    } else {
      final last = _whereClauses.removeLast();
      _whereClauses.add('($last OR $clause)');
    }
    if (params != null) _params.addAll(params);
    return this;
  }

  /// Adds an ORDER BY clause.
  SelectBuilder<T> orderBy(String column, {bool desc = false}) {
    _orderByClauses.add(desc ? '$column DESC' : column);
    return this;
  }

  /// Adds a GROUP BY clause.
  SelectBuilder<T> groupBy(String column) {
    _groupByClauses.add(column);
    return this;
  }

  /// Adds a HAVING clause.
  SelectBuilder<T> having(String clause, [Map<String, dynamic>? params]) {
    _havingClauses.add(clause);
    if (params != null) _params.addAll(params);
    return this;
  }

  /// Sets the LIMIT.
  SelectBuilder<T> limit(int value) {
    _limit = value;
    return this;
  }

  /// Sets the OFFSET.
  SelectBuilder<T> offset(int value) {
    _offset = value;
    return this;
  }

  /// Adds an INNER JOIN clause.
  SelectBuilder<T> join(String table, String on) {
    _joins.add('INNER JOIN $table ON $on');
    return this;
  }

  /// Adds a LEFT JOIN clause.
  SelectBuilder<T> leftJoin(String table, String on) {
    _joins.add('LEFT JOIN $table ON $on');
    return this;
  }

  /// Marks the query as DISTINCT.
  SelectBuilder<T> distinct() {
    _distinct = true;
    return this;
  }

  /// Builds the SQL and params without executing.
  (String sql, Map<String, dynamic> params) build() {
    final buffer = StringBuffer('SELECT ');

    if (_distinct) buffer.write('DISTINCT ');

    buffer.write(_columns.isEmpty ? '*' : _columns.join(', '));
    buffer.write(' FROM $_table');

    for (final j in _joins) {
      buffer.write(' $j');
    }

    if (_whereClauses.isNotEmpty) {
      buffer.write(' WHERE ${_whereClauses.join(' AND ')}');
    }

    if (_groupByClauses.isNotEmpty) {
      buffer.write(' GROUP BY ${_groupByClauses.join(', ')}');
    }

    if (_havingClauses.isNotEmpty) {
      buffer.write(' HAVING ${_havingClauses.join(' AND ')}');
    }

    if (_orderByClauses.isNotEmpty) {
      buffer.write(' ORDER BY ${_orderByClauses.join(', ')}');
    }

    final dialect = _db.dialect;

    if (_limit != null || _offset != null) {
      if (dialect == SqlDialect.mssql) {
        buffer.write(' OFFSET ${_offset ?? 0} ROWS');
        if (_limit != null) {
          buffer.write(' FETCH NEXT $_limit ROWS ONLY');
        }
      } else {
        if (_limit != null) buffer.write(' LIMIT $_limit');
        if (_offset != null) buffer.write(' OFFSET $_offset');
      }
    }

    return (buffer.toString(), Map<String, dynamic>.from(_params));
  }

  /// Executes the query and returns all rows mapped to `T`.
  Future<List<T>> list() async {
    final (sql, params) = build();
    final rows = await _db.query<Map<String, dynamic>>(sql, params);
    return rows.map((row) => _adapter.fromJson<T>(row)).toList();
  }

  /// Executes the query and returns the first row mapped to `T`, or `null`.
  Future<T?> first() async {
    final (sql, params) = build();
    final row =
        await _db.queryFirst<Map<String, dynamic>>(sql, params);
    if (row == null) return null;
    return _adapter.fromJson<T>(row);
  }

  /// Executes the query and returns a single scalar value.
  Future<V?> scalar<V>() async {
    final (sql, params) = build();
    return _db.scalar<V>(sql, params);
  }

  /// Executes a COUNT(*) query on the current filters.
  Future<int> count() async {
    final saved = List<String>.from(_columns);
    _columns
      ..clear()
      ..add('COUNT(*)');
    final result = await scalar<int>() ?? 0;
    _columns
      ..clear()
      ..addAll(saved);
    return result;
  }

  /// Executes a paginated query and returns a [PagedResult<T>].
  Future<PagedResult<T>> paged({
    required int page,
    required int pageSize,
  }) async {
    final (baseSql, params) = build();

    // Use AnakiDb.queryPaged which handles dialect-specific pagination
    return _db.queryPaged<T>(
      baseSql,
      params: params,
      page: page,
      pageSize: pageSize,
      map: (row) => _adapter.fromJson<T>(row),
    );
  }
}
