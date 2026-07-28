# Changelog

## 0.1.7

- `close()` now returns immediately: client shutdown is detached onto the driver's process-global runtime instead of being awaited with a 5s ceiling. Sessions and pending drops still complete in the background within milliseconds; only the SRV polling monitor's sleep drains on its own. Removes the residual 5s cost per `mongodb+srv://` close introduced by the 0.1.6 workaround

## 0.1.6

- Fix `close()` blocking ~59s for `mongodb+srv://` connections: the mongodb crate's SRV polling monitor sleeps up to 60s without observing the shutdown signal, and `Client::shutdown` waits for it. The driver now bounds shutdown at 5s — real cleanup (session end, pending drops, cancellation) still runs; only the join on the monitor's sleep is abandoned. Non-SRV connections close in microseconds as before

## 0.1.5

- Enable the mongodb crate's `socks5-proxy` feature: connection URIs now accept `proxyHost`/`proxyPort`/`proxyUsername`/`proxyPassword` (MongoDB driver spec), allowing connections through a SOCKS5 proxy — e.g. an SSH dynamic forward — which is required for replica-set/SRV topologies where local port-forwards cannot follow server-announced hostnames. Pure-Rust dependency (fast-socks5); cross-compilation via cargo-zigbuild remains green on all 5 platforms

## 0.1.4

- Fix native symbol collision when multiple anaki drivers are loaded in the same process: the driver now binds its FFI symbols from its own library handle first, falling back to the native-assets runtime for bundled builds

## 0.1.3

- Fix universal (arm64+x64) macOS builds: the build hook now copies the binary into the per-config output directory, so each architecture slice gets its own file (previously both slices pointed at the same dylib and lipo failed with duplicate architectures)

## 0.1.2

- Fix pub.dev packaging: native binaries are now really inside the published archive (0.1.1 tarballs were missing native_libs/ because a repo-root gitignore rule excluded them from `dart pub publish`)

## 0.1.1

- Native library loads via the native-assets asset id (works with `flutter build` framework bundling), with filesystem search as fallback (#6)
- New build target: Linux ARM64 (aarch64)

## 0.1.0

- Initial release: MongoDB document client (`AnakiMongoDb`/`MongoCollection`) over the AnakiORM native Rust connector.
- find/findOne/findPaged, insert/update/replace/delete, countDocuments, aggregate, distinct, indexes, `runCommand` escape hatch.
- Real multi-document transactions via ClientSession (requires a replica set).
- `ObjectId` value class and automatic extended-JSON codec (`{"$oid"}`/`{"$date"}` ↔ `ObjectId`/`DateTime`).
