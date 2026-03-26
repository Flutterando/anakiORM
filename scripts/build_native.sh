#!/bin/sh
#
# build_native.sh — Build Rust native libraries for AnakiORM drivers.
#
# Uses a SINGLE Rust crate (rust/) with feature flags to compile
# each database driver separately.
#
# Usage:
#   ./scripts/build_native.sh sqlite          # Build SQLite for all platforms
#   ./scripts/build_native.sh sqlite --local  # Build SQLite for local platform only
#   ./scripts/build_native.sh all             # Build all drivers for all platforms
#   ./scripts/build_native.sh all --local     # Build all drivers for local platform only
#   ./scripts/build_native.sh --check         # Check if all dependencies are installed
#
# Requirements:
#   - Rust toolchain via rustup
#   - zig (brew install zig)
#   - cargo-zigbuild (cargo install cargo-zigbuild)
#   - Rust targets: rustup target add x86_64-apple-darwin x86_64-unknown-linux-gnu x86_64-pc-windows-gnu
#

set -eu

# Ensure cargo is in PATH (for rustup installations)
if [ -f "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CRATE_DIR="$ROOT_DIR/rust"

DRIVERS="sqlite postgres mysql mssql"

# Targets for pub.dev distribution
ALL_TARGETS="aarch64-apple-darwin x86_64-apple-darwin x86_64-unknown-linux-gnu x86_64-pc-windows-gnu"

# ─── Target metadata (no associative arrays — POSIX compatible) ───

target_os() {
  case "$1" in
    aarch64-apple-darwin|x86_64-apple-darwin) echo "darwin" ;;
    x86_64-unknown-linux-gnu|aarch64-unknown-linux-gnu) echo "linux" ;;
    x86_64-pc-windows-gnu) echo "windows" ;;
  esac
}

target_arch() {
  case "$1" in
    aarch64-apple-darwin|aarch64-unknown-linux-gnu) echo "arm64" ;;
    x86_64-apple-darwin|x86_64-unknown-linux-gnu|x86_64-pc-windows-gnu) echo "x64" ;;
  esac
}

target_ext() {
  case "$1" in
    aarch64-apple-darwin|x86_64-apple-darwin) echo "dylib" ;;
    x86_64-unknown-linux-gnu|aarch64-unknown-linux-gnu) echo "so" ;;
    x86_64-pc-windows-gnu) echo "dll" ;;
  esac
}

target_prefix() {
  case "$1" in
    x86_64-pc-windows-gnu) echo "" ;;
    *) echo "lib" ;;
  esac
}

# ─── Helper Functions ───

print_info() {
  printf "${BLUE}ℹ${NC} %s\n" "$1"
}

print_success() {
  printf "${GREEN}✓${NC} %s\n" "$1"
}

print_warning() {
  printf "${YELLOW}⚠${NC} %s\n" "$1"
}

print_error() {
  printf "${RED}✗${NC} %s\n" "$1"
}

print_header() {
  printf "\n${BLUE}═══════════════════════════════════════════${NC}\n"
  printf "${BLUE} %s${NC}\n" "$1"
  printf "${BLUE}═══════════════════════════════════════════${NC}\n"
}

# ─── Dependency Check ───

check_dependencies() {
  print_header "Checking Dependencies"
  
  all_ok=true
  
  # Check rustup
  if command -v rustup >/dev/null 2>&1; then
    version=$(rustup --version 2>&1 | head -1)
    print_success "rustup: $version"
  else
    print_error "rustup: NOT FOUND"
    print_info "  Install: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    all_ok=false
  fi
  
  # Check cargo
  if command -v cargo >/dev/null 2>&1; then
    version=$(cargo --version)
    print_success "cargo: $version"
  else
    print_error "cargo: NOT FOUND"
    all_ok=false
  fi
  
  # Check zig
  if command -v zig >/dev/null 2>&1; then
    version=$(zig version)
    print_success "zig: $version"
  else
    print_error "zig: NOT FOUND"
    print_info "  Install: brew install zig"
    all_ok=false
  fi
  
  # Check cargo-zigbuild
  zigbuild_path="$HOME/.cargo/bin/cargo-zigbuild"
  if [ -x "$zigbuild_path" ]; then
    version=$("$zigbuild_path" --version 2>&1)
    print_success "cargo-zigbuild: $version"
  elif command -v cargo-zigbuild >/dev/null 2>&1; then
    version=$(cargo-zigbuild --version 2>&1)
    print_success "cargo-zigbuild: $version"
  else
    print_error "cargo-zigbuild: NOT FOUND"
    print_info "  Install: cargo install cargo-zigbuild"
    all_ok=false
  fi
  
  # Check Rust targets
  echo ""
  print_info "Checking Rust targets..."
  installed_targets=$(rustup target list --installed 2>/dev/null || echo "")
  
  for target in $ALL_TARGETS; do
    if echo "$installed_targets" | grep -q "^$target$"; then
      print_success "  $target"
    else
      print_error "  $target: NOT INSTALLED"
      print_info "    Install: rustup target add $target"
      all_ok=false
    fi
  done
  
  echo ""
  if $all_ok; then
    print_success "All dependencies are installed!"
    return 0
  else
    print_error "Some dependencies are missing. Install them and try again."
    return 1
  fi
}

# ─── Functions ───

detect_local_target() {
  _os="$(uname -s)"
  _arch="$(uname -m)"

  case "$_os" in
    Darwin)
      case "$_arch" in
        arm64) echo "aarch64-apple-darwin" ;;
        x86_64) echo "x86_64-apple-darwin" ;;
        *) echo "unknown" ;;
      esac
      ;;
    Linux)
      case "$_arch" in
        x86_64) echo "x86_64-unknown-linux-gnu" ;;
        aarch64) echo "aarch64-unknown-linux-gnu" ;;
        *) echo "unknown" ;;
      esac
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

build_driver_for_target() {
  driver="$1"
  target="$2"
  native_libs_dir="$ROOT_DIR/packages/anaki_$driver/native_libs"

  os_str="$(target_os "$target")"
  arch_str="$(target_arch "$target")"
  ext="$(target_ext "$target")"
  prefix="$(target_prefix "$target")"

  output_name="${prefix}anaki_${driver}-${os_str}-${arch_str}.${ext}"

  print_info "Building anaki_$driver for $target..."

  local_target="$(detect_local_target)"

  # Build the unified crate with the driver's feature flag
  if [ "$target" = "$local_target" ]; then
    # Local target: use regular cargo build
    cargo build --release \
      --manifest-path "$CRATE_DIR/Cargo.toml" \
      --target "$target" \
      --features "$driver" 2>&1 | tail -5
  else
    # Cross-compilation: use cargo-zigbuild
    zigbuild_cmd="$HOME/.cargo/bin/cargo-zigbuild"
    if [ ! -x "$zigbuild_cmd" ]; then
      zigbuild_cmd="cargo-zigbuild"
      if ! command -v "$zigbuild_cmd" >/dev/null 2>&1; then
        print_error "'cargo-zigbuild' not installed. Install with: cargo install cargo-zigbuild"
        print_info "Skipping cross-compilation for $target"
        return 1
      fi
    fi
    "$zigbuild_cmd" zigbuild --release \
      --manifest-path "$CRATE_DIR/Cargo.toml" \
      --target "$target" \
      --features "$driver" 2>&1 | tail -5
  fi

  # The crate name is "anaki_native", so the output is libanaki_native.{ext}
  if [ "$ext" = "dll" ]; then
    built_lib="$CRATE_DIR/target/$target/release/anaki_native.$ext"
  else
    built_lib="$CRATE_DIR/target/$target/release/libanaki_native.$ext"
  fi

  if [ ! -f "$built_lib" ]; then
    print_error "Built library not found at: $built_lib"
    print_info "Searching in $CRATE_DIR/target/$target/release/..."
    find "$CRATE_DIR/target/$target/release/" -maxdepth 1 \( -name "*.so" -o -name "*.dylib" -o -name "*.dll" \) 2>/dev/null || true
    return 1
  fi

  # Copy and rename to the driver-specific name in the Dart package
  mkdir -p "$native_libs_dir"
  cp "$built_lib" "$native_libs_dir/$output_name"

  size=$(du -h "$native_libs_dir/$output_name" | cut -f1)
  print_success "$output_name ($size)"
}

build_driver() {
  driver="$1"
  shift

  print_header "Building: anaki_$driver (--features $driver)"

  for target in "$@"; do
    build_driver_for_target "$driver" "$target"
  done
}

# ─── Main ───

DRIVER_ARG="${1:-}"
LOCAL_ONLY=false

# Handle --check flag
if [ "$DRIVER_ARG" = "--check" ]; then
  check_dependencies
  exit $?
fi

if [ -z "$DRIVER_ARG" ]; then
  echo "Usage: $0 <driver|all> [--local]"
  echo "       $0 --check"
  echo ""
  echo "Drivers: $DRIVERS"
  echo ""
  echo "Options:"
  echo "  --local    Build only for current platform"
  echo "  --check    Verify all dependencies are installed"
  echo ""
  echo "Examples:"
  echo "  $0 sqlite          # Build SQLite for all platforms"
  echo "  $0 sqlite --local  # Build SQLite for local platform only"
  echo "  $0 all             # Build all drivers for all platforms"
  echo "  $0 all --local     # Build all drivers for local platform"
  echo "  $0 --check         # Check dependencies"
  exit 1
fi

if [ "${2:-}" = "--local" ]; then
  LOCAL_ONLY=true
fi

# Determine targets
if $LOCAL_ONLY; then
  LOCAL_TARGET="$(detect_local_target)"
  if [ "$LOCAL_TARGET" = "unknown" ]; then
    print_error "Could not detect local platform."
    exit 1
  fi
  TARGETS="$LOCAL_TARGET"
  print_info "Mode: local only ($LOCAL_TARGET)"
else
  TARGETS="$ALL_TARGETS"
  print_info "Mode: all platforms (cross-compilation via cargo-zigbuild)"
fi

# Determine drivers
if [ "$DRIVER_ARG" = "all" ]; then
  SELECTED_DRIVERS="$DRIVERS"
else
  # Validate driver name
  VALID=false
  for d in $DRIVERS; do
    if [ "$d" = "$DRIVER_ARG" ]; then
      VALID=true
      break
    fi
  done
  if ! $VALID; then
    print_error "Unknown driver '$DRIVER_ARG'. Available: $DRIVERS"
    exit 1
  fi
  SELECTED_DRIVERS="$DRIVER_ARG"
fi

print_info "Drivers: $SELECTED_DRIVERS"
print_info "Crate: $CRATE_DIR"

# Build each driver
for driver in $SELECTED_DRIVERS; do
  # shellcheck disable=SC2086
  build_driver "$driver" $TARGETS
done

print_header "Build Summary"

for driver in $SELECTED_DRIVERS; do
  native_dir="$ROOT_DIR/packages/anaki_$driver/native_libs"
  if [ -d "$native_dir" ]; then
    printf "\n${GREEN}anaki_$driver:${NC}\n"
    for file in "$native_dir"/*; do
      if [ -f "$file" ]; then
        filename=$(basename "$file")
        size=$(du -h "$file" | cut -f1)
        printf "  ${GREEN}✓${NC} %s (%s)\n" "$filename" "$size"
      fi
    done
  fi
done

echo ""
print_success "Build complete!"
