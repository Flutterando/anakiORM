import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:anaki_orm/anaki_orm.dart';
import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'mongo_driver_base.dart';
import 'mongo_wire.dart';

/// FFI driver for MongoDB.
///
/// Communicates with the native Rust connector. Command envelopes are sent
/// as JSON through the shared `anaki_query`/`anaki_execute` exports.
class MongoDriver implements MongoDriverBase {
  final String? _uri;
  final String _host;
  final int _port;
  final String? _username;
  final String? _password;
  final String? _authSource;
  final String _database;
  final PoolConfig _poolConfig;

  late final AnakiMongoDbBindings _bindings;
  bool _loaded = false;

  /// Creates a driver from discrete connection parameters.
  MongoDriver({
    required String host,
    int port = 27017,
    String? username,
    String? password,
    String? authSource,
    required String database,
    PoolConfig poolConfig = const PoolConfig(),
  })  : _uri = null,
        _host = host,
        _port = port,
        _username = username,
        _password = password,
        _authSource = authSource,
        _database = database,
        _poolConfig = poolConfig;

  /// Creates a driver from a `mongodb://` / `mongodb+srv://` URI.
  ///
  /// [database] stays explicit so collection routing is unambiguous
  /// regardless of the URI path.
  MongoDriver.uri(
    String uri, {
    required String database,
    PoolConfig poolConfig = const PoolConfig(),
  })  : _uri = uri,
        _host = 'localhost',
        _port = 27017,
        _username = null,
        _password = null,
        _authSource = null,
        _database = database,
        _poolConfig = poolConfig;

  void _ensureLoaded() {
    if (_loaded) return;
    // Prefer the native-assets runtime (resolves the asset bundled by
    // `dart build`/`flutter build`, e.g. the macOS framework layout).
    // Fall back to the filesystem search for environments without the
    // build hook (monorepo dev, prebuilt dylib next to the executable).
    try {
      _bindings = AnakiMongoDbBindings.fromNativeAssets();
    } catch (_) {
      _bindings = AnakiMongoDbBindings.fromLibrary(_loadLibrary());
    }
    _loaded = true;
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
      final libUri = Uri.parse('package:anaki_mongodb/anaki_mongodb.dart');
      final resolved = Isolate.resolvePackageUriSync(libUri);
      if (resolved != null) {
        // resolved points to lib/anaki_mongodb.dart — go up to package root
        final pkgRoot = resolved.resolve('../');
        packageNativeLibsDir = pkgRoot.resolve('native_libs/').toFilePath();
      }
    } catch (_) {}

    final String libName;
    final String platformLibName;
    if (Platform.isMacOS) {
      libName = 'libanaki_mongodb.dylib';
      final arch = _isArm64() ? 'arm64' : 'x64';
      platformLibName = 'libanaki_mongodb-darwin-$arch.dylib';
    } else if (Platform.isLinux) {
      libName = 'libanaki_mongodb.so';
      final arch = _isArm64() ? 'arm64' : 'x64';
      platformLibName = 'libanaki_mongodb-linux-$arch.so';
    } else if (Platform.isWindows) {
      libName = 'anaki_mongodb.dll';
      platformLibName = 'anaki_mongodb-windows-x64.dll';
    } else {
      throw const ConnectionException(
        'Unsupported platform',
        details: 'AnakiORM MongoDB supports macOS, Linux, and Windows.',
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
      'packages/anaki_mongodb/native_libs/$platformLibName',
      'packages/anaki_mongodb/native_libs/$libName',
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

  @override
  Future<void> rawOpen() async {
    _ensureLoaded();

    final config = jsonEncode({
      if (_uri != null) 'uri': _uri,
      if (_uri == null) ...{
        'host': _host,
        'port': _port,
        if (_username != null) 'username': _username,
        if (_password != null) 'password': _password,
        if (_authSource != null) 'auth_source': _authSource,
      },
      'database': _database,
      'min_connections': _poolConfig.minConnections,
      'max_connections': _poolConfig.maxConnections,
      // Driver default is 30s, which would make open() hang on a bad host.
      'server_selection_timeout_ms': 5000,
    });

    final configPtr = config.toNativeUtf8();
    try {
      final result = _callFfi(_bindings.open(configPtr));
      checkWireError(_parseResponse(result));
    } finally {
      calloc.free(configPtr);
    }
  }

  @override
  Future<void> rawClose() async {
    if (!_loaded) return;
    final result = _callFfi(_bindings.close());
    checkWireError(_parseResponse(result));
  }

  @override
  Future<bool> rawPing() async {
    final result = _callFfi(_bindings.ping());
    final response = _parseResponse(result);
    checkWireError(response);
    final ok = response['ok'] as Map<String, dynamic>;
    return ok['success'] as bool;
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    Map<String, dynamic> envelope,
  ) async {
    final sql = jsonEncode(envelope);
    final sqlPtr = sql.toNativeUtf8();
    final paramsPtr = '{}'.toNativeUtf8();

    try {
      final result = _callFfi(_bindings.query(sqlPtr, paramsPtr));
      final response = _parseResponse(result);
      checkWireError(response, statement: sql);

      final ok = response['ok'] as Map<String, dynamic>;
      final rows = ok['rows'] as List<dynamic>;
      return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    } finally {
      calloc.free(sqlPtr);
      calloc.free(paramsPtr);
    }
  }

  @override
  Future<int> rawExecute(Map<String, dynamic> envelope) async {
    final sql = jsonEncode(envelope);
    final sqlPtr = sql.toNativeUtf8();
    final paramsPtr = '{}'.toNativeUtf8();

    try {
      final result = _callFfi(_bindings.execute(sqlPtr, paramsPtr));
      final response = _parseResponse(result);
      checkWireError(response, statement: sql);

      final ok = response['ok'] as Map<String, dynamic>;
      return ok['rows_affected'] as int;
    } finally {
      calloc.free(sqlPtr);
      calloc.free(paramsPtr);
    }
  }

  @override
  Future<int> rawExecuteBatch(
    Map<String, dynamic> envelope,
    List<Map<String, dynamic>> documents,
  ) async {
    final sql = jsonEncode(envelope);
    final sqlPtr = sql.toNativeUtf8();
    final paramsListPtr = jsonEncode(documents).toNativeUtf8();

    try {
      final result = _callFfi(_bindings.executeBatch(sqlPtr, paramsListPtr));
      final response = _parseResponse(result);
      checkWireError(response, statement: sql);

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
    checkWireError(_parseResponse(result));
  }

  @override
  Future<void> rawCommit() async {
    final result = _callFfi(_bindings.commit());
    checkWireError(_parseResponse(result));
  }

  @override
  Future<void> rawRollback() async {
    final result = _callFfi(_bindings.rollback());
    checkWireError(_parseResponse(result));
  }
}
