import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:anaki_orm/anaki_orm.dart';
import 'package:ffi/ffi.dart';

import 'bindings.dart';

/// SQL Server driver for AnakiORM.
///
/// Communicates with the native Rust connector (tiberius) via FFI.
///
/// ```dart
/// final driver = MssqlDriver(
///   host: 'localhost',
///   database: 'mydb',
///   username: 'sa',
///   password: 'YourStrong!Passw0rd',
/// );
/// final db = AnakiDb(driver);
/// await db.open();
/// ```
class MssqlDriver implements AnakiDriver {
  final String _host;
  final int _port;
  final String _username;
  final String _password;
  final String _database;
  final bool _trustCert;
  final bool? _encrypt;

  late final AnakiMssqlBindings _bindings;
  bool _loaded = false;

  @override
  SqlDialect get dialect => SqlDialect.mssql;

  /// Creates a new SQL Server driver.
  MssqlDriver({
    required String host,
    int port = 1433,
    required String username,
    String password = '',
    required String database,
    bool trustCert = false,
    bool? encrypt,
  }) : _host = host,
       _port = port,
       _username = username,
       _password = password,
       _database = database,
       _trustCert = trustCert,
       _encrypt = encrypt;

  void _ensureLoaded() {
    if (!_loaded) {
      final lib = _loadLibrary();
      _bindings = AnakiMssqlBindings.fromLibrary(lib);
      _loaded = true;
    }
  }

  static bool _isArm64() {
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
    String? packageNativeLibsDir;
    try {
      final libUri = Uri.parse('package:anaki_mssql/anaki_mssql.dart');
      final resolved = Isolate.resolvePackageUriSync(libUri);
      if (resolved != null) {
        final pkgRoot = resolved.resolve('../');
        packageNativeLibsDir = pkgRoot.resolve('native_libs/').toFilePath();
      }
    } catch (_) {}

    final String libName;
    final String platformLibName;
    if (Platform.isMacOS) {
      libName = 'libanaki_mssql.dylib';
      final arch = _isArm64() ? 'arm64' : 'x64';
      platformLibName = 'libanaki_mssql-darwin-$arch.dylib';
    } else if (Platform.isLinux) {
      libName = 'libanaki_mssql.so';
      final arch = _isArm64() ? 'arm64' : 'x64';
      platformLibName = 'libanaki_mssql-linux-$arch.so';
    } else if (Platform.isWindows) {
      libName = 'anaki_mssql.dll';
      platformLibName = 'anaki_mssql-windows-x64.dll';
    } else {
      throw const ConnectionException(
        'Unsupported platform',
        details: 'AnakiORM MSSQL supports macOS, Linux, and Windows.',
      );
    }

    final searchPaths = [
      '${File(Platform.resolvedExecutable).parent.path}/$libName',
      libName,
      'native_libs/$platformLibName',
      'native_libs/$libName',
      'packages/anaki_mssql/native_libs/$platformLibName',
      'packages/anaki_mssql/native_libs/$libName',
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
      'host': _host,
      'port': _port,
      'username': _username,
      'password': _password,
      'database': _database,
      'trust_cert': _trustCert,
      if (_encrypt != null) 'encrypt': _encrypt,
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
