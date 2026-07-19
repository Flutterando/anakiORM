# anaki_redis

Redis key-value client for [AnakiORM](https://github.com/anaki/anaki_orm), backed by the same native Rust connector infrastructure as the SQL drivers.

Unlike the SQL drivers, this package does **not** implement `AnakiDriver` and is not used through `AnakiDb` — Redis is not a SQL database. It ships a dedicated typed client.

## Usage

```dart
import 'package:anaki_redis/anaki_redis.dart';

final redis = AnakiRedis(host: 'localhost', password: 'secret');
// or: AnakiRedis.url('redis://:secret@localhost:6379/0')
await redis.open();

// Strings + expiry
await redis.set('session:42', 'token', ttl: Duration(minutes: 30));
final token = await redis.get('session:42');

// Hashes, lists, sets, sorted sets
await redis.hsetAll('user:1', {'name': 'Ana', 'city': 'SP'});
final user = await redis.hgetall('user:1');
await redis.zadd('board', {'ana': 10.5});

// Atomic batch (MULTI/EXEC)
await redis.pipeline((p) {
  p.incr('stats:visits');
  p.expire('stats:visits', Duration(days: 1));
});

// Anything else via the escape hatch
final range = await redis.command(['GETRANGE', 'session:42', 0, 3]);

await redis.close();
```

### Object cache with RowAdapter

```dart
final redis = AnakiRedis(host: 'localhost', adapter: RowAdapter(dson.fromJson, dson.toJson));
await redis.setObject('user:1', userDto, ttl: Duration(minutes: 5));
final cached = await redis.getObject<UserDTO>('user:1');
```

## Semantics and limits (v1)

- `pipeline()` is atomic (MULTI/EXEC) but returns only the applied-command count — per-command replies cannot be mapped back over the wire. Need replies? Issue sequential commands.
- Interactive transactions (`begin/commit/rollback`) are intentionally unsupported; the native connector rejects them.
- Not supported: pub/sub, blocking commands (`BLPOP`...), `WATCH`, TLS (`tls: true` fails at connect). Streams, scripting and other commands are reachable via `command()`.
- Binary-unsafe values are decoded as lossy UTF-8.
- `QueryException.sql` carries the rendered command (values included — avoid logging verbatim if sensitive).

## Native library

The Rust connector is built per platform with:

```sh
./scripts/build_native.sh redis --local
```

Integration tests expect a local Redis: `docker compose up` from `example/shelf_redis_example/`.
