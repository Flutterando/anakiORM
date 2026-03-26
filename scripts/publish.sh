#!/bin/sh
#
# publish.sh — Publish AnakiORM packages to pub.dev
#
# This script publishes packages in the correct order (dependencies first).
# It can run in dry-run mode to verify everything before actual publish.
#
# Usage:
#   ./scripts/publish.sh              # Dry-run (verify only)
#   ./scripts/publish.sh --publish    # Actually publish to pub.dev
#   ./scripts/publish.sh --package anaki_sqlite  # Publish single package
#   ./scripts/publish.sh --prepare    # Prepare pubspec.yaml for publishing
#   ./scripts/publish.sh --restore    # Restore pubspec.yaml to development mode
#
# Requirements:
#   - All native libraries must be built (run ./scripts/build_native.sh all)
#   - You must be logged in to pub.dev (run: dart pub login)
#

set -eu

# Ensure cargo is in PATH
if [ -f "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Packages in dependency order (anaki_orm first, then drivers)
PACKAGES="anaki_orm anaki_sqlite anaki_postgres anaki_mysql anaki_mssql"

# Drivers that need native libs
DRIVERS="anaki_sqlite anaki_postgres anaki_mysql anaki_mssql"

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

print_warning() {
  printf "${YELLOW}⚠${NC} %s\n" "$1"
}

print_info() {
  printf "${BLUE}ℹ${NC} %s\n" "$1"
}

# Note: With workspace configuration, no need to prepare/restore pubspec.yaml files.
# The workspace handles dependency resolution automatically.

# ─── Verify native libraries exist ───

verify_native_libs() {
  print_header "Verifying Native Libraries"
  
  all_ok=true
  
  for driver in $DRIVERS; do
    native_dir="$ROOT_DIR/packages/$driver/native_libs"
    printf "\n${BLUE}$driver:${NC}\n"
    
    for platform in $PLATFORMS; do
      case "$platform" in
        darwin-*) ext="dylib"; prefix="lib" ;;
        linux-*) ext="so"; prefix="lib" ;;
        windows-*) ext="dll"; prefix="" ;;
      esac
      
      # Driver name without anaki_ prefix for filename
      driver_short="${driver#anaki_}"
      expected_file="$native_dir/${prefix}anaki_${driver_short}-${platform}.${ext}"
      
      if [ -f "$expected_file" ]; then
        size=$(du -h "$expected_file" | cut -f1)
        print_success "$platform ($size)"
      else
        print_error "$platform - MISSING: $expected_file"
        all_ok=false
      fi
    done
  done
  
  echo ""
  if $all_ok; then
    print_success "All native libraries present!"
    return 0
  else
    print_error "Some native libraries are missing!"
    print_info "Run: ./scripts/build_native.sh all"
    return 1
  fi
}

# ─── Verify pub.dev login ───

verify_login() {
  print_header "Verifying pub.dev Login"
  
  # Check if credentials exist
  if [ -f "$HOME/.config/dart/pub-credentials.json" ] || [ -f "$HOME/.pub-cache/credentials.json" ]; then
    print_success "pub.dev credentials found"
    return 0
  else
    print_error "Not logged in to pub.dev"
    print_info "Run: dart pub login"
    return 1
  fi
}

# ─── Publish a single package ───

publish_package() {
  package="$1"
  dry_run="$2"
  
  pkg_dir="$ROOT_DIR/packages/$package"
  
  if [ ! -d "$pkg_dir" ]; then
    print_error "Package not found: $pkg_dir"
    return 1
  fi
  
  print_header "Publishing: $package"
  
  cd "$pkg_dir"
  
  # Get version from pubspec.yaml
  version=$(grep "^version:" pubspec.yaml | sed 's/version: //')
  print_info "Version: $version"
  
  if [ "$dry_run" = "true" ]; then
    print_info "Running dry-run..."
    # Capture output to check for actual errors vs warnings
    output=$(dart pub publish --dry-run 2>&1) || true
    echo "$output"
    
    # Check for actual errors (not just warnings)
    if echo "$output" | grep -q "Package validation found the following.*error"; then
      print_error "Dry-run failed with errors!"
      return 1
    elif echo "$output" | grep -q "Sorry, your package is missing"; then
      print_error "Dry-run failed - package missing requirements!"
      return 1
    else
      print_success "Dry-run passed!"
    fi
  else
    print_warning "Publishing to pub.dev..."
    if dart pub publish --force; then
      print_success "Published $package v$version!"
    else
      print_error "Failed to publish $package"
      return 1
    fi
  fi
  
  cd "$ROOT_DIR"
}

# ─── Main ───

DRY_RUN=true
SINGLE_PACKAGE=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --publish)
      DRY_RUN=false
      shift
      ;;
    --package)
      SINGLE_PACKAGE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --publish           Actually publish (default is dry-run)"
      echo "  --package <name>    Publish single package"
      echo "  -h, --help          Show this help"
      echo ""
      echo "Packages (in publish order):"
      echo "  $PACKAGES"
      echo ""
      echo "Examples:"
      echo "  $0                           # Dry-run all packages"
      echo "  $0 --publish                 # Publish all packages"
      echo "  $0 --package anaki_sqlite    # Dry-run single package"
      echo "  $0 --publish --package anaki_orm  # Publish single package"
      exit 0
      ;;
    *)
      print_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

print_header "AnakiORM Publish Script"

if [ "$DRY_RUN" = "true" ]; then
  print_info "Mode: DRY-RUN (use --publish to actually publish)"
else
  print_warning "Mode: PUBLISH (will upload to pub.dev)"
fi

# Verify native libs
if ! verify_native_libs; then
  exit 1
fi

# Verify login (only for actual publish)
if [ "$DRY_RUN" = "false" ]; then
  if ! verify_login; then
    exit 1
  fi
fi

# Determine which packages to publish
if [ -n "$SINGLE_PACKAGE" ]; then
  PACKAGES_TO_PUBLISH="$SINGLE_PACKAGE"
else
  PACKAGES_TO_PUBLISH="$PACKAGES"
fi

# Publish packages
failed=false
for package in $PACKAGES_TO_PUBLISH; do
  if ! publish_package "$package" "$DRY_RUN"; then
    failed=true
    if [ "$DRY_RUN" = "false" ]; then
      print_error "Stopping due to publish failure"
      exit 1
    fi
  fi
done

# Summary
print_header "Summary"

if [ "$failed" = "true" ]; then
  print_error "Some packages failed validation"
  exit 1
else
  if [ "$DRY_RUN" = "true" ]; then
    print_success "All packages passed dry-run!"
    echo ""
    print_info "To publish for real, run:"
    echo "  ./scripts/publish.sh --publish"
  else
    print_success "All packages published successfully!"
  fi
fi
