part of 'redis_client.dart';

/// Command recorder for [AnakiRedis.pipeline].
///
/// Methods enqueue commands synchronously; the batch runs atomically
/// (MULTI/EXEC) when the builder callback returns.
class RedisPipeline {
  final List<List<String>> _commands = [];

  RedisPipeline._();

  void _add(List<Object?> parts) => _commands.add(encodeRedisArgs(parts));

  /// Enqueues an arbitrary command.
  void command(List<Object?> parts) => _add(parts);

  /// Enqueues SET (optionally with a PX ttl).
  void set(String key, String value, {Duration? ttl}) => _add([
        'SET',
        key,
        value,
        if (ttl != null) ...['PX', ttl.inMilliseconds],
      ]);

  /// Enqueues DEL.
  void del(List<String> keys) => _add(['DEL', ...keys]);

  /// Enqueues INCR.
  void incr(String key) => _add(['INCR', key]);

  /// Enqueues INCRBY.
  void incrBy(String key, int by) => _add(['INCRBY', key, by]);

  /// Enqueues PEXPIRE.
  void expire(String key, Duration ttl) =>
      _add(['PEXPIRE', key, ttl.inMilliseconds]);

  /// Enqueues HSET for a single field.
  void hset(String key, String field, String value) =>
      _add(['HSET', key, field, value]);

  /// Enqueues HSET for multiple fields.
  void hsetAll(String key, Map<String, String> fields) => _add([
        'HSET',
        key,
        for (final e in fields.entries) ...[e.key, e.value],
      ]);

  /// Enqueues LPUSH.
  void lpush(String key, List<String> values) =>
      _add(['LPUSH', key, ...values]);

  /// Enqueues RPUSH.
  void rpush(String key, List<String> values) =>
      _add(['RPUSH', key, ...values]);

  /// Enqueues SADD.
  void sadd(String key, List<String> members) =>
      _add(['SADD', key, ...members]);

  /// Enqueues SREM.
  void srem(String key, List<String> members) =>
      _add(['SREM', key, ...members]);

  /// Enqueues ZADD.
  void zadd(String key, Map<String, double> memberScores) => _add([
        'ZADD',
        key,
        for (final e in memberScores.entries) ...[e.value, e.key],
      ]);
}
