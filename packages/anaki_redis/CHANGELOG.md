# Changelog

## 0.1.0

- Initial release: typed Redis client (`AnakiRedis`) over the AnakiORM native Rust connector.
- Strings, expiry, hashes, lists, sets, sorted sets, keys/scan, JSON/object cache helpers.
- Atomic MULTI/EXEC batches via `pipeline()`; generic `command()` escape hatch.
