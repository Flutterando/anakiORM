# Changelog

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
