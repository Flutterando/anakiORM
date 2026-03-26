import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:anaki_orm/anaki_orm.dart';
import 'package:ffi/ffi.dart';

import 'bindings.dart';

/// SQLite driver for AnakiORM.
///
/// Communicates with the native Rust connector via FFI.
///
/// ```dart
/// final driver = SqliteDriver('/path/to/database.db');
/// final db = AnakiDb(driver);
/// await db.open();
/// ```
class SqliteDriver implements AnakiDriver {
  final String _path;
  final PoolConfig _poolConfig;

  late final AnakiSqliteBindings _bindings;
  bool _loaded = false;

  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  /// Creates a new SQLite driver.
  ///
  /// [path] is the file path to the SQLite database.
  /// Use `:memory:` for an in-memory database.
  SqliteDriver(this._path, {PoolConfig poolConfig = const PoolConfig()})
    : _poolConfig = poolConfig;

  void _ensureLoaded() {
    if (!_loaded) {
      final lib = _loadLibrary();
      _bindings = AnakiSqliteBindings.fromLibrary(lib);
      _loaded = true;
    }
  }

  static bool _isArm64() {
    // dart:io doesn't expose arch directly; use uname on unix, assume x64 on windows
    if (Platform.isWindows) return false;
    try {
      final result = Process.runSync('uname', ['-m']);
      final arch = (result.stdout as String).trim();
      return arch == 'arm64' || arch == 'aarch64';
    } catch (_) {
      return false;
    }
  }

  DynamicLibrary _loadLibrary() {
    // Resolve the package's own directory for native_libs lookup
    String? packageNativeLibsDir;
    try {
      final libUri = Uri.parse('package:anaki_sqlite/anaki_sqlite.dart');
      final resolved = Isolate.resolvePackageUriSync(libUri);
      if (resolved != null) {
        // resolved points to lib/anaki_sqlite.dart — go up to package root
        final pkgRoot = resolved.resolve('../');
        packageNativeLibsDir = pkgRoot.resolve('native_libs/').toFilePath();
      }
    } catch (_) {}

    final String libName;
    final String platformLibName;
    if (Platform.isMacOS) {
      libName = 'libanaki_sqlite.dylib';
      final arch = _isArm64() ? 'arm64' : 'x64';
      platformLibName = 'libanaki_sqlite-darwin-$arch.dylib';
    } else if (Platform.isLinux) {
      libName = 'libanaki_sqlite.so';
      final arch = _isArm64() ? 'arm64' : 'x64';
      platformLibName = 'libanaki_sqlite-linux-$arch.so';
    } else if (Platform.isWindows) {
      libName = 'anaki_sqlite.dll';
      platformLibName = 'anaki_sqlite-windows-x64.dll';
    } else {
      throw const ConnectionException(
        'Unsupported platform',
        details: 'AnakiORM SQLite supports macOS, Linux, and Windows.',
      );
    }

    // Try loading from multiple locations
    final searchPaths = [
      // Next to the executable (generic name)
      '${File(Platform.resolvedExecutable).parent.path}/$libName',
      // Current directory
      libName,
      // native_libs directory — platform-specific name (from build script)
      'native_libs/$platformLibName',
      // native_libs directory — generic name
      'native_libs/$libName',
      // Package native_libs (monorepo development)
      'packages/anaki_sqlite/native_libs/$platformLibName',
      'packages/anaki_sqlite/native_libs/$libName',
      // Resolved package path (works for path: dependencies)
      if (packageNativeLibsDir != null) '$packageNativeLibsDir$platformLibName',
      if (packageNativeLibsDir != null) '$packageNativeLibsDir$libName',
    ];

    for (final path in searchPaths) {
      try {
        return DynamicLibrary.open(path);
      } catch (_) {
        continue;
      }
    }

    // Try system default
    try {
      return DynamicLibrary.open(libName);
    } catch (_) {
      throw ConnectionException(
        'Failed to load native library: $libName',
        details:
            'Searched in: ${searchPaths.join(', ')}. '
            'Make sure the native library is built and available.',
      );
    }
  }

  String _callFfi(Pointer<Utf8> resultPtr) {
    final resultStr = resultPtr.toDartString();
    _bindings.freeString(resultPtr);
    return resultStr;
  }

  Map<String, dynamic> _parseResponse(String json) {
    return jsonDecode(json) as Map<String, dynamic>;
  }

  void _checkError(Map<String, dynamic> response) {
    if (response.containsKey('error')) {
      final error = response['error'] as Map<String, dynamic>;
      final code = error['code'] as String;
      final message = error['message'] as String;
      final details = error['details'] as String?;

      switch (code) {
        case 'CONNECTION_ERROR':
          throw ConnectionException(message, details: details);
        case 'QUERY_ERROR':
          throw QueryException(message, details: details);
        case 'TRANSACTION_ERROR':
          throw TransactionException(message, details: details);
        default:
          throw AnakiException(message, details: details);
      }
    }
  }

  @override
  Future<void> rawOpen() async {
    _ensureLoaded();

    final config = jsonEncode({
      'path': _path,
      'min_connections': _poolConfig.minConnections,
      'max_connections': _poolConfig.maxConnections,
    });

    final configPtr = config.toNativeUtf8();
    try {
      final result = _callFfi(_bindings.open(configPtr));
      final response = _parseResponse(result);
      _checkError(response);
    } finally {
      calloc.free(configPtr);
    }
  }

  @override
  Future<void> rawClose() async {
    if (!_loaded) return;
    final result = _callFfi(_bindings.close());
    final response = _parseResponse(result);
    _checkError(response);
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql,
    Map<String, dynamic>? params,
  ) async {
    final sqlPtr = sql.toNativeUtf8();
    final paramsStr = jsonEncode(params ?? {});
    final paramsPtr = paramsStr.toNativeUtf8();

    try {
      final result = _callFfi(_bindings.query(sqlPtr, paramsPtr));
      final response = _parseResponse(result);
      _checkError(response);

      final ok = response['ok'] as Map<String, dynamic>;
      final rows = ok['rows'] as List<dynamic>;
      return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    } finally {
      calloc.free(sqlPtr);
      calloc.free(paramsPtr);
    }
  }

  @override
  Future<int> rawExecute(String sql, Map<String, dynamic>? params) async {
    final sqlPtr = sql.toNativeUtf8();
    final paramsStr = jsonEncode(params ?? {});
    final paramsPtr = paramsStr.toNativeUtf8();

    try {
      final result = _callFfi(_bindings.execute(sqlPtr, paramsPtr));
      final response = _parseResponse(result);
      _checkError(response);

      final ok = response['ok'] as Map<String, dynamic>;
      return ok['rows_affected'] as int;
    } finally {
      calloc.free(sqlPtr);
      calloc.free(paramsPtr);
    }
  }

  @override
  Future<int> rawExecuteBatch(
    String sql,
    List<Map<String, dynamic>> paramsList,
  ) async {
    final sqlPtr = sql.toNativeUtf8();
    final paramsListStr = jsonEncode(paramsList);
    final paramsListPtr = paramsListStr.toNativeUtf8();

    try {
      final result = _callFfi(_bindings.executeBatch(sqlPtr, paramsListPtr));
      final response = _parseResponse(result);
      _checkError(response);

      final ok = response['ok'] as Map<String, dynamic>;
      return ok['rows_affected'] as int;
    } finally {
      calloc.free(sqlPtr);
      calloc.free(paramsListPtr);
    }
  }

  @override
  Future<void> rawBeginTransaction() async {
    final result = _callFfi(_bindings.beginTransaction());
    final response = _parseResponse(result);
    _checkError(response);
  }

  @override
  Future<void> rawCommit() async {
    final result = _callFfi(_bindings.commit());
    final response = _parseResponse(result);
    _checkError(response);
  }

  @override
  Future<void> rawRollback() async {
    final result = _callFfi(_bindings.rollback());
    final response = _parseResponse(result);
    _checkError(response);
  }

  @override
  Future<bool> rawPing() async {
    final result = _callFfi(_bindings.ping());
    final response = _parseResponse(result);
    _checkError(response);

    final ok = response['ok'] as Map<String, dynamic>;
    return ok['success'] as bool;
  }
}
