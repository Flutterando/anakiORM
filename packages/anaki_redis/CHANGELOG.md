# Changelog

## 0.1.1

- Native library loads via the native-assets asset id (works with `flutter build` framework bundling), with filesystem search as fallback (#6)
- New build target: Linux ARM64 (aarch64)

## 0.1.0

- Initial release: typed Redis client (`AnakiRedis`) over the AnakiORM native Rust connector.
- Strings, expiry, hashes, lists, sets, sorted sets, keys/scan, JSON/object cache helpers.
- Atomic MULTI/EXEC batches via `pipeline()`; generic `command()` escape hatch.
