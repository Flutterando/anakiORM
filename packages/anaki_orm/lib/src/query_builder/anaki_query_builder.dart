import '../db.dart';
import 'row_adapter.dart';
import 'select_builder.dart';
import 'insert_builder.dart';
import 'update_builder.dart';
import 'delete_builder.dart';

/// Fluent query builder for database operations.
///
/// Receives an [AnakiDb] for execution and a [RowAdapter] for mapping.
/// The table and generic type are specified on each operation.
///
/// ```dart
/// final qb = AnakiQueryBuilder(db, adapter);
///
/// final active = await qb
///     .select<UserDTO>('users')
///     .where('active = @active', {'active': true})
///     .list();
/// ```
class AnakiQueryBuilder {
  /// The database instance used to execute queries.
  final AnakiDb db;

  /// The global adapter for row ↔ object conversion.
  final RowAdapter adapter;

  /// Creates a query builder using [db] and [adapter].
  AnakiQueryBuilder(this.db, this.adapter);

  /// Starts a SELECT query on [table], mapping rows to `T`.
  SelectBuilder<T> select<T>(String table) =>
      SelectBuilder<T>(db, adapter, table);

  /// Starts an INSERT statement on [table], serializing entities of type `T`.
  InsertBuilder<T> insert<T>(String table) =>
      InsertBuilder<T>(db, adapter, table);

  /// Starts an UPDATE statement on [table].
  UpdateBuilder update(String table) => UpdateBuilder(db, adapter, table);

  /// Starts a DELETE statement on [table].
  DeleteBuilder delete(String table) => DeleteBuilder(db, table);
}
