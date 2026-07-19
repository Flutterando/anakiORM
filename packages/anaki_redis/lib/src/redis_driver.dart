import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:anaki_orm/anaki_orm.dart';
import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'redis_driver_base.dart';
import 'redis_wire.dart';

/// FFI driver for Redis.
///
/// Communicates with the native Rust connector. Commands are sent as JSON
/// arrays through the `anaki_query` export; atomic pipelines through
/// `anaki_execute_batch`.
class RedisDriver implements RedisDriverBase {
  final String _host;
  final int _port;
  final String? _username;
  final String? _password;
  final int _db;
  final bool _tls;
  final PoolConfig _poolConfig;

  late final AnakiRedisBindings _bindings;
  bool _loaded = false;

  /// Creates a new Redis driver.
  RedisDriver({
    required String host,
    int port = 6379,
    String? username,
    String? password,
    int db = 0,
    bool tls = false,
    PoolConfig poolConfig = const PoolConfig(),
  })  : _host = host,
        _port = port,
        _username = username,
        _password = password,
        _db = db,
        _tls = tls,
        _poolConfig = poolConfig;

  void _ensureLoaded() {
    if (!_loaded) {
      final lib = _loadLibrary();
      _bindings = AnakiRedisBindings.fromLibrary(lib);
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
      final libUri = Uri.parse('package:anaki_redis/anaki_redis.dart');
      final resolved = Isolate.resolvePackageUriSync(libUri);
      if (resolved != null) {
        // resolved points to lib/anaki_redis.dart — go up to package root
        final pkgRoot = resolved.resolve('../');
        packageNativeLibsDir = pkgRoot.resolve('native_libs/').toFilePath();
      }
    } catch (_) {}

    final String libName;
    final String platformLibName;
    if (Platform.isMacOS) {
      libName = 'libanaki_redis.dylib';
      final arch = _isArm64() ? 'arm64' : 'x64';
      platformLibName = 'libanaki_redis-darwin-$arch.dylib';
    } else if (Platform.isLinux) {
      libName = 'libanaki_redis.so';
      final arch = _isArm64() ? 'arm64' : 'x64';
      platformLibName = 'libanaki_redis-linux-$arch.so';
    } else if (Platform.isWindows) {
      libName = 'anaki_redis.dll';
      platformLibName = 'anaki_redis-windows-x64.dll';
    } else {
      throw const ConnectionException(
        'Unsupported platform',
        details: 'AnakiORM Redis supports macOS, Linux, and Windows.',
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
      'packages/anaki_redis/native_libs/$platformLibName',
      'packages/anaki_redis/native_libs/$libName',
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
      'host': _host,
      'port': _port,
      'db': _db,
      'tls': _tls,
      if (_username != null) 'username': _username,
      if (_password != null) 'password': _password,
      'min_connections': _poolConfig.minConnections,
      'max_connections': _poolConfig.maxConnections,
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
  Future<dynamic> rawCommand(List<String> parts) async {
    final sqlPtr = jsonEncode(parts).toNativeUtf8();
    final paramsPtr = '{}'.toNativeUtf8();

    try {
      final result = _callFfi(_bindings.query(sqlPtr, paramsPtr));
      final response = _parseResponse(result);
      checkWireError(response, command: parts.join(' '));
      return unwrapQueryResult(response);
    } finally {
      calloc.free(sqlPtr);
      calloc.free(paramsPtr);
    }
  }

  @override
  Future<int> rawPipeline(List<List<String>> commands) async {
    final sqlPtr = '[]'.toNativeUtf8();
    final paramsListPtr = jsonEncode([
      for (final cmd in commands) {'cmd': cmd},
    ]).toNativeUtf8();

    try {
      final result = _callFfi(_bindings.executeBatch(sqlPtr, paramsListPtr));
      final response = _parseResponse(result);
      checkWireError(response, command: 'MULTI/EXEC pipeline');
      final ok = response['ok'] as Map<String, dynamic>;
      return ok['rows_affected'] as int;
    } finally {
      calloc.free(sqlPtr);
      calloc.free(paramsListPtr);
    }
  }
}
