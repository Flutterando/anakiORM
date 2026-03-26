# Anaki ORM — Build Guide

> How to compile native libraries for all platforms

---

## 1. Prerequisites

### 1.1 Rust via rustup

Rust must be installed via `rustup` (not via Homebrew):

```bash
# Check if rustup is installed
rustup --version

# If not installed:
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### 1.2 Zig

Zig is used as the cross-compilation toolchain:

```bash
# macOS
brew install zig

# Linux (Ubuntu/Debian)
sudo apt install zig

# Verify installation
zig version
```

### 1.3 cargo-zigbuild

Tool that integrates Zig with Cargo for cross-compilation:

```bash
cargo install cargo-zigbuild

# Verify installation
cargo zigbuild --version
```

### 1.4 Rust Targets

Add compilation targets for each platform:

```bash
rustup target add aarch64-apple-darwin   # macOS ARM64
rustup target add x86_64-apple-darwin    # macOS x64
rustup target add x86_64-unknown-linux-gnu  # Linux x64
rustup target add x86_64-pc-windows-gnu  # Windows x64
```

### 1.5 Verify Everything

Use the script to verify all dependencies are installed:

```bash
./scripts/build_native.sh --check
```

Expected output:
```
═══════════════════════════════════════════
 Checking Dependencies
═══════════════════════════════════════════
✓ rustup: rustup 1.29.0
✓ cargo: cargo 1.94.1
✓ zig: 0.15.2
✓ cargo-zigbuild: cargo-zigbuild 0.22.1

ℹ Checking Rust targets...
✓   aarch64-apple-darwin
✓   x86_64-apple-darwin
✓   x86_64-unknown-linux-gnu
✓   x86_64-pc-windows-gnu

✓ All dependencies are installed!
```

---

## 2. Compilation

### 2.1 Local Build (Development)

To compile only for the current platform:

```bash
# A specific driver
./scripts/build_native.sh sqlite --local

# All drivers
./scripts/build_native.sh all --local
```

### 2.2 Cross-Platform Build

To compile for all platforms (requires zig + cargo-zigbuild):

```bash
# A specific driver
./scripts/build_native.sh sqlite

# All drivers
./scripts/build_native.sh all
```

### 2.3 Release Build (pub.dev)

To prepare a complete release:

```bash
./scripts/build_release.sh
```

This script:
1. Verifies all dependencies
2. Compiles all drivers for all platforms
3. Verifies all binaries were generated
4. Shows a summary with sizes

---

## 3. Available Drivers

| Driver | Feature Flag | Rust Crate |
|--------|--------------|------------|
| `sqlite` | `--features sqlite` | sqlx |
| `postgres` | `--features postgres` | sqlx |
| `mysql` | `--features mysql` | sqlx |
| `mssql` | `--features mssql` | tiberius |

---

## 4. Supported Platforms

| Platform | Target | Extension |
|------------|--------|----------|
| macOS ARM64 | `aarch64-apple-darwin` | `.dylib` |
| macOS x64 | `x86_64-apple-darwin` | `.dylib` |
| Linux x64 | `x86_64-unknown-linux-gnu` | `.so` |
| Windows x64 | `x86_64-pc-windows-gnu` | `.dll` |

---

## 5. Output Structure

Binaries are copied to `packages/anaki_<driver>/native_libs/`:

```
packages/
├── anaki_sqlite/native_libs/
│   ├── libanaki_sqlite-darwin-arm64.dylib
│   ├── libanaki_sqlite-darwin-x64.dylib
│   ├── libanaki_sqlite-linux-x64.so
│   └── anaki_sqlite-windows-x64.dll
├── anaki_postgres/native_libs/
│   └── ...
├── anaki_mysql/native_libs/
│   └── ...
└── anaki_mssql/native_libs/
    └── ...
```

---

## 6. Troubleshooting

### 6.1 "rustup: command not found"

Rust was installed via Homebrew, not via rustup:

```bash
# Uninstall from Homebrew
brew uninstall rust

# Install via rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Restart terminal
```

### 6.2 "error: linker not found"

Zig is not installed or not in PATH:

```bash
brew install zig
```

### 6.3 "target not found"

Missing target in rustup:

```bash
rustup target add x86_64-unknown-linux-gnu
```

### 6.4 Build fails for Windows

The Windows target uses GNU toolchain. If there are problems:

```bash
# Check if target is installed
rustup target list --installed | grep windows

# Reinstall if necessary
rustup target remove x86_64-pc-windows-gnu
rustup target add x86_64-pc-windows-gnu
```

### 6.5 Binary not found after build

The Rust crate is called `anaki_native`, so the output is `libanaki_native.{ext}`. The script renames it to `libanaki_<driver>-<platform>.{ext}`.

If the binary is not found, check:
```bash
ls -la rust/target/*/release/*.{dylib,so,dll} 2>/dev/null
```

---

## 7. Publishing to pub.dev

After compiling all binaries:

```bash
# 1. Verify all binaries exist
./scripts/build_release.sh

# 2. Update version in pubspec.yaml files
# packages/anaki_orm/pubspec.yaml
# packages/anaki_sqlite/pubspec.yaml
# etc.

# 3. Dry-run to verify
cd packages/anaki_sqlite
dart pub publish --dry-run

# 4. Publish
dart pub publish
```

**Publishing order:**
1. `anaki_orm` (core, no native dependencies)
2. `anaki_sqlite`
3. `anaki_postgres`
4. `anaki_mysql`
5. `anaki_mssql`

---

## 8. References

- [Architecture](./architecture.md)
- [Drivers Guide](./drivers.md)
- [CONTRIBUTING.md](../CONTRIBUTING.md)
