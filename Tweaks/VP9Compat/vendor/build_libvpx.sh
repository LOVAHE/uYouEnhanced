#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBVPX_SOURCE="$SCRIPT_DIR/libvpx"
BUILD_DIR="$SCRIPT_DIR/libvpx_ios"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos --find clang)"
CXX="$(xcrun --sdk iphoneos --find clang++)"
AR="$(xcrun --sdk iphoneos --find ar)"
STRIP="$(xcrun --sdk iphoneos --find strip)"
NM="$(xcrun --sdk iphoneos --find nm)"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

CC="$CC" CXX="$CXX" AR="$AR" STRIP="$STRIP" NM="$NM" \
"$LIBVPX_SOURCE/configure" \
    --target=arm64-darwin-gcc \
    --disable-examples \
    --disable-tools \
    --disable-docs \
    --disable-unit-tests \
    --disable-vp8 \
    --disable-vp9-encoder \
    --enable-vp9-decoder \
    --extra-cflags="-miphoneos-version-min=14.0 -isysroot $SDK"

make -j"$(sysctl -n hw.ncpu)" libvpx.a
