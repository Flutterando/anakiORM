# Changelog

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
