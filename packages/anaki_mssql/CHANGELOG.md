# Changelog

## 0.1.4

- Fix native symbol collision when multiple anaki drivers are loaded in the same process: the driver now binds its FFI symbols from its own library handle first, falling back to the native-assets runtime for bundled builds

## 0.1.3

- Fix universal (arm64+x64) macOS builds: the build hook now copies the binary into the per-config output directory, so each architecture slice gets its own file (previously both slices pointed at the same dylib and lipo failed with duplicate architectures)

## 0.1.2

- Fix pub.dev packaging: native binaries are now really inside the published archive (0.1.1 tarballs were missing native_libs/ because a repo-root gitignore rule excluded them from `dart pub publish`)

## 0.1.1

- DATETIME/DATETIME2/DATETIMEOFFSET/DATE/TIME, DECIMAL/NUMERIC and GUID columns now decode correctly (previously returned null); timestamps as RFC3339/ISO-8601, decimals as precision-preserving strings
- FFI exports are panic-safe: internal panics become error responses instead of aborting the host process (#2)
- Query rows keep the SELECT column order instead of returning alphabetically sorted keys (#5)
- Native library loads via the native-assets asset id (works with `flutter build` framework bundling), with filesystem search as fallback (#6)
- Prebuilt native binaries included for all supported platforms (#4)
- New build target: Linux ARM64 (aarch64)

## 0.1.0

- Initial release
- Core `AnakiDb` class with SQL-first API
- `AnakiQueryBuilder` for fluent queries
- `Migrator` and `Seeder` for database migrations
- Support for SQLite, PostgreSQL, MySQL, and SQL Server
- Cross-platform native libraries (macOS, Linux, Windows)
