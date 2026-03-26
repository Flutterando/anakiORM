#!/bin/sh
#
# build_release.sh — Build all native libraries for pub.dev release.
#
# This script builds all drivers for all supported platforms,
# then verifies that all expected binaries were generated.
#
# Usage:
#   ./scripts/build_release.sh
#
# This is equivalent to:
#   ./scripts/build_native.sh all
#
# But with additional verification and reporting.
#

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRIVERS="sqlite postgres mysql mssql"
PLATFORMS="darwin-arm64 darwin-x64 linux-x64 windows-x64"

print_header() {
  printf "\n${BLUE}═══════════════════════════════════════════${NC}\n"
  printf "${BLUE} %s${NC}\n" "$1"
  printf "${BLUE}═══════════════════════════════════════════${NC}\n"
}

print_success() {
  printf "${GREEN}✓${NC} %s\n" "$1"
}

print_error() {
  printf "${RED}✗${NC} %s\n" "$1"
}

print_info() {
  printf "${BLUE}ℹ${NC} %s\n" "$1"
}

# ─── Main ───

print_header "AnakiORM Release Build"

echo ""
print_info "This will build all drivers for all platforms."
print_info "Drivers: $DRIVERS"
print_info "Platforms: $PLATFORMS"
echo ""

# Check dependencies first
print_info "Checking dependencies..."
if ! "$SCRIPT_DIR/build_native.sh" --check; then
  print_error "Dependencies check failed. Please install missing dependencies."
  exit 1
fi

# Build all drivers for all platforms
print_header "Building All Drivers"

"$SCRIPT_DIR/build_native.sh" all

# Verify all binaries exist
print_header "Verifying Binaries"

all_ok=true
total_size=0

for driver in $DRIVERS; do
  native_dir="$ROOT_DIR/packages/anaki_$driver/native_libs"
  printf "\n${BLUE}anaki_$driver:${NC}\n"
  
  for platform in $PLATFORMS; do
    case "$platform" in
      darwin-*) ext="dylib"; prefix="lib" ;;
      linux-*) ext="so"; prefix="lib" ;;
      windows-*) ext="dll"; prefix="" ;;
    esac
    
    expected_file="$native_dir/${prefix}anaki_${driver}-${platform}.${ext}"
    
    if [ -f "$expected_file" ]; then
      size=$(du -h "$expected_file" | cut -f1)
      size_bytes=$(stat -f%z "$expected_file" 2>/dev/null || stat -c%s "$expected_file" 2>/dev/null || echo 0)
      total_size=$((total_size + size_bytes))
      print_success "$platform ($size)"
    else
      print_error "$platform - MISSING"
      all_ok=false
    fi
  done
done

# Summary
print_header "Release Summary"

total_mb=$(echo "scale=2; $total_size / 1048576" | bc 2>/dev/null || echo "N/A")

echo ""
if $all_ok; then
  print_success "All binaries generated successfully!"
  print_info "Total size: ${total_mb} MB"
  echo ""
  print_info "Next steps:"
  echo "  1. Test each driver on its target platform"
  echo "  2. Update version in pubspec.yaml files"
  echo "  3. Run: dart pub publish --dry-run"
  echo "  4. Run: dart pub publish"
else
  print_error "Some binaries are missing!"
  print_info "Check the build output above for errors."
  exit 1
fi
