part of 'mongo_db.dart';

/// Typed operations over a single MongoDB collection.
///
/// Obtained via [AnakiMongoDb.collection]; cheap to create, holds no state.
class MongoCollection {
  final AnakiMongoDb _db;

  /// The collection name.
  final String name;

  MongoCollection._(this._db, this.name);

  /// Finds documents matching [filter].
  ///
  /// If [map] is provided each document is transformed with it; otherwise the
  /// client's [RowAdapter] (when configured) maps to `T`.
  Future<List<T>> find<T>([
    Map<String, dynamic> filter = const {},
    Map<String, dynamic>? sort,
    Map<String, dynamic>? projection,
    int? skip,
    int? limit,
    T Function(Map<String, dynamic>)? map,
  ]) async {
    final rows = await _db._query({
      'op': 'find',
      'collection': name,
      'filter': filter,
      if (sort != null) 'sort': sort,
      if (projection != null) 'projection': projection,
      if (skip != null) 'skip': skip,
      if (limit != null) 'limit': limit,
    });
    return _db._mapRows(rows, map);
  }

  /// Finds the first document matching [filter], or `null`.
  Future<T?> findOne<T>([
    Map<String, dynamic> filter = const {},
    Map<String, dynamic>? sort,
    Map<String, dynamic>? projection,
    T Function(Map<String, dynamic>)? map,
  ]) async {
    final rows = await _db._query({
      'op': 'findOne',
      'collection': name,
      'filter': filter,
      if (sort != null) 'sort': sort,
      if (projection != null) 'projection': projection,
    });
    if (rows.isEmpty) return null;
    return _db._mapRows([rows.first], map).first;
  }

  /// Finds documents with pagination.
  ///
  /// Runs a `countDocuments` for the total plus a skip/limit `find`.
  /// Always pass [sort] for deterministic pages.
  Future<PagedResult<T>> findPaged<T>({
    Map<String, dynamic> filter = const {},
    Map<String, dynamic>? sort,
    Map<String, dynamic>? projection,
    required int page,
    required int pageSize,
    T Function(Map<String, dynamic>)? map,
  }) async {
    final total = await countDocuments(filter);
    final data = await find<T>(
      filter,
      sort,
      projection,
      (page - 1) * pageSize,
      pageSize,
      map,
    );
    return PagedResult<T>(
      data: data,
      total: total,
      page: page,
      pageSize: pageSize,
    );
  }

  /// Inserts [document] and returns its `_id`.
  ///
  /// When the document has no `_id`, a client-side [ObjectId] is generated
  /// and injected (standard MongoDB client behavior) — no extra round-trip.
  Future<dynamic> insertOne(Map<String, dynamic> document) async {
    final doc = Map<String, dynamic>.from(document);
    final id = doc.putIfAbsent('_id', () => ObjectId());
    await _db._execute({
      'op': 'insertOne',
      'collection': name,
      'document': doc,
    });
    return id;
  }

  /// Inserts [documents] in a single batch; returns how many were inserted.
  Future<int> insertMany(List<Map<String, dynamic>> documents) async {
    if (documents.isEmpty) return 0;
    return _db._executeBatch(
      {'op': 'insertOne', 'collection': name},
      documents,
    );
  }

  /// Updates the first document matching [filter]; returns the number of
  /// modified documents (1 when an upsert inserted).
  Future<int> updateOne(
    Map<String, dynamic> filter,
    Map<String, dynamic> update, {
    bool upsert = false,
  }) {
    return _db._execute({
      'op': 'updateOne',
      'collection': name,
      'filter': filter,
      'update': update,
      'upsert': upsert,
    });
  }

  /// Updates every document matching [filter].
  Future<int> updateMany(
    Map<String, dynamic> filter,
    Map<String, dynamic> update, {
    bool upsert = false,
  }) {
    return _db._execute({
      'op': 'updateMany',
      'collection': name,
      'filter': filter,
      'update': update,
      'upsert': upsert,
    });
  }

  /// Replaces the first document matching [filter] with [replacement].
  Future<int> replaceOne(
    Map<String, dynamic> filter,
    Map<String, dynamic> replacement, {
    bool upsert = false,
  }) {
    return _db._execute({
      'op': 'replaceOne',
      'collection': name,
      'filter': filter,
      'replacement': replacement,
      'upsert': upsert,
    });
  }

  /// Deletes the first document matching [filter].
  Future<int> deleteOne(Map<String, dynamic> filter) {
    return _db._execute({
      'op': 'deleteOne',
      'collection': name,
      'filter': filter,
    });
  }

  /// Deletes every document matching [filter].
  Future<int> deleteMany(Map<String, dynamic> filter) {
    return _db._execute({
      'op': 'deleteMany',
      'collection': name,
      'filter': filter,
    });
  }

  /// Counts documents matching [filter].
  Future<int> countDocuments([Map<String, dynamic> filter = const {}]) async {
    final rows = await _db._query({
      'op': 'countDocuments',
      'collection': name,
      'filter': filter,
    });
    final raw = rows.isNotEmpty ? rows.first['count'] : 0;
    return (raw is int) ? raw : int.tryParse('$raw') ?? 0;
  }

  /// Runs an aggregation [pipeline].
  Future<List<T>> aggregate<T>(
    List<Map<String, dynamic>> pipeline, {
    T Function(Map<String, dynamic>)? map,
  }) async {
    final rows = await _db._query({
      'op': 'aggregate',
      'collection': name,
      'pipeline': pipeline,
    });
    return _db._mapRows(rows, map);
  }

  /// Distinct values of [field] among documents matching [filter].
  Future<List<dynamic>> distinct(
    String field, [
    Map<String, dynamic> filter = const {},
  ]) async {
    final rows = await _db._query({
      'op': 'distinct',
      'collection': name,
      'field': field,
      'filter': filter,
    });
    return rows.map((r) => r['value']).toList();
  }

  /// Creates an index over [keys] (e.g. `{'email': 1}`).
  Future<void> createIndex(
    Map<String, dynamic> keys, {
    String? name,
    bool unique = false,
  }) async {
    await _db._execute({
      'op': 'createIndex',
      'collection': this.name,
      'keys': keys,
      if (name != null) 'name': name,
      'unique': unique,
    });
  }

  /// Drops the index named [name].
  Future<void> dropIndex(String name) async {
    await _db._execute({
      'op': 'dropIndex',
      'collection': this.name,
      'name': name,
    });
  }

  /// Drops the whole collection.
  Future<void> drop() async {
    await _db._execute({'op': 'dropCollection', 'collection': name});
  }
}
