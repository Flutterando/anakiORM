import 'dart:convert';

import 'package:anaki_orm/anaki_orm.dart';

import 'redis_codec.dart';
import 'redis_driver.dart';
import 'redis_driver_base.dart';

part 'redis_pipeline.dart';

/// Typed Redis client for AnakiORM.
///
/// ```dart
/// final redis = AnakiRedis(host: 'localhost', password: 'secret');
/// await redis.open();
///
/// await redis.set('user:1:name', 'Ana', ttl: Duration(minutes: 5));
/// final name = await redis.get('user:1:name');
///
/// await redis.pipeline((p) {
///   p.incr('stats:visits');
///   p.expire('stats:visits', Duration(days: 1));
/// });
///
/// await redis.close();
/// ```
///
/// Not supported in v1 (documented cuts): pub/sub, blocking commands
/// (BLPOP...), WATCH, streams and scripting — the generic [command] escape
/// hatch reaches anything else.
class AnakiRedis {
  final RedisDriverBase _driver;
  final RowAdapter? _adapter;
  bool _isOpen = false;

  /// Creates a client connecting with discrete parameters.
  AnakiRedis({
    required String host,
    int port = 6379,
    String? username,
    String? password,
    int db = 0,
    bool tls = false,
    PoolConfig poolConfig = const PoolConfig(),
    RowAdapter? adapter,
  })  : _driver = RedisDriver(
          host: host,
          port: port,
          username: username,
          password: password,
          db: db,
          tls: tls,
          poolConfig: poolConfig,
        ),
        _adapter = adapter;

  /// Creates a client from a `redis://` (or `rediss://`, TLS) URL.
  ///
  /// Format: `redis://[user:password@]host[:port][/db]`.
  factory AnakiRedis.url(
    String url, {
    PoolConfig poolConfig = const PoolConfig(),
    RowAdapter? adapter,
  }) {
    final uri = Uri.parse(url);
    if (uri.scheme != 'redis' && uri.scheme != 'rediss') {
      throw ArgumentError.value(url, 'url', 'Expected a redis:// or rediss:// URL');
    }
    String? username;
    String? password;
    if (uri.userInfo.isNotEmpty) {
      final sep = uri.userInfo.indexOf(':');
      if (sep < 0) {
        password = uri.userInfo;
      } else {
        username = sep == 0 ? null : uri.userInfo.substring(0, sep);
        password = uri.userInfo.substring(sep + 1);
      }
    }
    final db = uri.pathSegments.isNotEmpty
        ? int.tryParse(uri.pathSegments.first) ?? 0
        : 0;
    return AnakiRedis(
      host: uri.host.isEmpty ? 'localhost' : uri.host,
      port: uri.hasPort ? uri.port : 6379,
      username: username,
      password: password,
      db: db,
      tls: uri.scheme == 'rediss',
      poolConfig: poolConfig,
      adapter: adapter,
    );
  }

  /// Creates a client over a custom driver (dependency injection / tests).
  AnakiRedis.withDriver(RedisDriverBase driver, {RowAdapter? adapter})
      : _driver = driver,
        _adapter = adapter;

  /// Whether the connection is currently open.
  bool get isOpen => _isOpen;

  /// Opens the connection.
  Future<void> open() async {
    await _driver.rawOpen();
    _isOpen = true;
  }

  /// Closes the connection.
  Future<void> close() async {
    await _driver.rawClose();
    _isOpen = false;
  }

  /// Checks if the connection is alive.
  Future<bool> ping() async {
    _ensureOpen();
    return _driver.rawPing();
  }

  void _ensureOpen() {
    if (!_isOpen) {
      throw const NotConnectedException();
    }
  }

  Future<dynamic> _run(List<Object?> parts) {
    _ensureOpen();
    return _driver.rawCommand(encodeRedisArgs(parts));
  }

  /// Sends an arbitrary command and returns the normalized reply.
  ///
  /// Escape hatch for commands without a typed wrapper:
  /// `await redis.command(['GETRANGE', 'key', 0, 3])`.
  Future<dynamic> command(List<Object?> parts) => _run(parts);

  // ─── Strings ───

  /// Gets the value of [key], or `null` if it does not exist.
  Future<String?> get(String key) async => await _run(['GET', key]) as String?;

  /// Sets [key] to [value], optionally expiring after [ttl].
  Future<void> set(String key, String value, {Duration? ttl}) async {
    await _run([
      'SET',
      key,
      value,
      if (ttl != null) ...['PX', ttl.inMilliseconds],
    ]);
  }

  /// Gets multiple keys at once; missing keys map to `null`.
  Future<List<String?>> mget(List<String> keys) async =>
      replyAsNullableStringList(await _run(['MGET', ...keys]));

  /// Sets multiple key/value pairs atomically.
  Future<void> mset(Map<String, String> entries) async {
    await _run([
      'MSET',
      for (final e in entries.entries) ...[e.key, e.value],
    ]);
  }

  /// Increments [key] by 1 and returns the new value.
  Future<int> incr(String key) async => replyAsInt(await _run(['INCR', key]));

  /// Increments [key] by [by] and returns the new value.
  Future<int> incrBy(String key, int by) async =>
      replyAsInt(await _run(['INCRBY', key, by]));

  /// Decrements [key] by 1 and returns the new value.
  Future<int> decr(String key) async => replyAsInt(await _run(['DECR', key]));

  /// Deletes [keys]; returns how many existed.
  Future<int> del(List<String> keys) async =>
      replyAsInt(await _run(['DEL', ...keys]));

  /// Whether [key] exists.
  Future<bool> exists(String key) async =>
      replyAsBool(await _run(['EXISTS', key]));

  // ─── Expiry ───

  /// Sets a time-to-live on [key]; returns false if the key does not exist.
  Future<bool> expire(String key, Duration ttl) async =>
      replyAsBool(await _run(['PEXPIRE', key, ttl.inMilliseconds]));

  /// Remaining time-to-live of [key], or `null` if the key does not exist
  /// or has no expiry (disambiguate with [exists]).
  Future<Duration?> ttl(String key) async {
    final ms = replyAsInt(await _run(['PTTL', key]));
    if (ms < 0) return null;
    return Duration(milliseconds: ms);
  }

  /// Removes the expiry from [key]; returns false if it had none.
  Future<bool> persist(String key) async =>
      replyAsBool(await _run(['PERSIST', key]));

  // ─── Hashes ───

  /// Sets a hash field; returns true if the field was created.
  Future<bool> hset(String key, String field, String value) async =>
      replyAsBool(await _run(['HSET', key, field, value]));

  /// Sets multiple hash fields; returns how many were created.
  Future<int> hsetAll(String key, Map<String, String> fields) async =>
      replyAsInt(await _run([
        'HSET',
        key,
        for (final e in fields.entries) ...[e.key, e.value],
      ]));

  /// Gets a hash field, or `null` if missing.
  Future<String?> hget(String key, String field) async =>
      await _run(['HGET', key, field]) as String?;

  /// Gets all fields of a hash (empty map for a missing key).
  Future<Map<String, String>> hgetall(String key) async =>
      replyAsStringMap(await _run(['HGETALL', key]));

  /// Deletes hash fields; returns how many existed.
  Future<int> hdel(String key, List<String> fields) async =>
      replyAsInt(await _run(['HDEL', key, ...fields]));

  /// Whether a hash field exists.
  Future<bool> hexists(String key, String field) async =>
      replyAsBool(await _run(['HEXISTS', key, field]));

  /// Lists the field names of a hash.
  Future<List<String>> hkeys(String key) async =>
      replyAsStringList(await _run(['HKEYS', key]));

  // ─── Lists ───

  /// Prepends [values]; returns the new list length.
  Future<int> lpush(String key, List<String> values) async =>
      replyAsInt(await _run(['LPUSH', key, ...values]));

  /// Appends [values]; returns the new list length.
  Future<int> rpush(String key, List<String> values) async =>
      replyAsInt(await _run(['RPUSH', key, ...values]));

  /// Pops from the head, or `null` if empty.
  Future<String?> lpop(String key) async =>
      await _run(['LPOP', key]) as String?;

  /// Pops from the tail, or `null` if empty.
  Future<String?> rpop(String key) async =>
      await _run(['RPOP', key]) as String?;

  /// Returns the elements between [start] and [stop] (inclusive).
  Future<List<String>> lrange(String key, int start, int stop) async =>
      replyAsStringList(await _run(['LRANGE', key, start, stop]));

  /// Length of the list.
  Future<int> llen(String key) async => replyAsInt(await _run(['LLEN', key]));

  // ─── Sets ───

  /// Adds [members]; returns how many were new.
  Future<int> sadd(String key, List<String> members) async =>
      replyAsInt(await _run(['SADD', key, ...members]));

  /// Removes [members]; returns how many existed.
  Future<int> srem(String key, List<String> members) async =>
      replyAsInt(await _run(['SREM', key, ...members]));

  /// All members of the set.
  Future<Set<String>> smembers(String key) async =>
      replyAsStringList(await _run(['SMEMBERS', key])).toSet();

  /// Whether [member] belongs to the set.
  Future<bool> sismember(String key, String member) async =>
      replyAsBool(await _run(['SISMEMBER', key, member]));

  /// Cardinality of the set.
  Future<int> scard(String key) async =>
      replyAsInt(await _run(['SCARD', key]));

  // ─── Sorted sets ───

  /// Adds members with scores; returns how many were new.
  Future<int> zadd(String key, Map<String, double> memberScores) async =>
      replyAsInt(await _run([
        'ZADD',
        key,
        for (final e in memberScores.entries) ...[e.value, e.key],
      ]));

  /// Members between ranks [start] and [stop], ordered by score.
  Future<List<String>> zrange(String key, int start, int stop) async =>
      replyAsStringList(await _run(['ZRANGE', key, start, stop]));

  /// Members with their scores between ranks [start] and [stop].
  Future<List<({String member, double score})>> zrangeWithScores(
    String key,
    int start,
    int stop,
  ) async =>
      replyAsScoredMembers(
        await _run(['ZRANGE', key, start, stop, 'WITHSCORES']),
      );

  /// Removes [members]; returns how many existed.
  Future<int> zrem(String key, List<String> members) async =>
      replyAsInt(await _run(['ZREM', key, ...members]));

  /// Score of [member], or `null` if absent.
  Future<double?> zscore(String key, String member) async =>
      replyAsDoubleOrNull(await _run(['ZSCORE', key, member]));

  /// Cardinality of the sorted set.
  Future<int> zcard(String key) async =>
      replyAsInt(await _run(['ZCARD', key]));

  // ─── Keys / server ───

  /// Keys matching [pattern]. O(N) over the keyspace — dev/test use only;
  /// prefer [scan] in production.
  Future<List<String>> keys(String pattern) async =>
      replyAsStringList(await _run(['KEYS', pattern]));

  /// Iterates the keyspace incrementally. Start with `cursor: 0` and repeat
  /// with the returned cursor until it comes back as 0.
  Future<({int cursor, List<String> keys})> scan({
    int cursor = 0,
    String? match,
    int? count,
  }) async {
    final reply = await _run([
      'SCAN',
      cursor,
      if (match != null) ...['MATCH', match],
      if (count != null) ...['COUNT', count],
    ]) as List;
    return (
      cursor: replyAsInt(reply[0]),
      keys: replyAsStringList(reply[1]),
    );
  }

  /// Removes all keys of the current database.
  Future<void> flushDb() async {
    await _run(['FLUSHDB']);
  }

  // ─── JSON / object cache ───

  /// Stores [value] JSON-encoded.
  Future<void> setJson(String key, Object? value, {Duration? ttl}) =>
      set(key, jsonEncode(value), ttl: ttl);

  /// Reads a JSON-encoded value, or `null` if the key does not exist.
  Future<dynamic> getJson(String key) async {
    final raw = await get(key);
    return raw == null ? null : jsonDecode(raw);
  }

  /// Caches an entity serialized through the configured [RowAdapter].
  Future<void> setObject<T>(String key, T value, {Duration? ttl}) {
    final adapter = _requireAdapter();
    return set(key, jsonEncode(adapter.toJson<T>(value)), ttl: ttl);
  }

  /// Reads an entity deserialized through the configured [RowAdapter].
  Future<T?> getObject<T>(String key) async {
    final adapter = _requireAdapter();
    final raw = await get(key);
    if (raw == null) return null;
    return adapter.fromJson<T>(jsonDecode(raw) as Map<String, dynamic>);
  }

  RowAdapter _requireAdapter() {
    final adapter = _adapter;
    if (adapter == null) {
      throw StateError(
        'No RowAdapter configured. Pass `adapter:` to the AnakiRedis '
        'constructor to use setObject/getObject.',
      );
    }
    return adapter;
  }

  // ─── Pipeline ───

  /// Runs an atomic MULTI/EXEC batch and returns how many commands ran.
  ///
  /// The recorder only exposes write-shaped commands: the wire protocol
  /// returns a single count for the whole batch, so per-command replies
  /// cannot be mapped back. Need replies? Issue sequential commands.
  Future<int> pipeline(void Function(RedisPipeline p) build) async {
    _ensureOpen();
    final p = RedisPipeline._();
    build(p);
    if (p._commands.isEmpty) return 0;
    return _driver.rawPipeline(p._commands);
  }
}
