#!/bin/bash
set -e

# Download and setup C2PA libraries for macOS SigningServer
# This script ensures the SigningServer has all required libraries

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGNING_SERVER_ROOT="$(dirname "$SCRIPT_DIR")"
LIBS_DIR="${SIGNING_SERVER_ROOT}/libs"
TEMP_DIR="${SIGNING_SERVER_ROOT}/.build/temp"

# Read configuration from base xcconfig
XCCONFIG_FILE="${SIGNING_SERVER_ROOT}/../Configurations/Base.xcconfig"
if [ ! -f "$XCCONFIG_FILE" ]; then
    echo "Error: Base.xcconfig not found"
    exit 1
fi

# Extract values from xcconfig
GITHUB_ORG=$(grep "^GITHUB_ORG" "$XCCONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
C2PA_VERSION=$(grep "^C2PA_VERSION" "$XCCONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')

if [ -z "$GITHUB_ORG" ] || [ -z "$C2PA_VERSION" ]; then
    echo "Error: Could not read GITHUB_ORG or C2PA_VERSION from xcconfig"
    exit 1
fi

echo "macOS C2PA Library Setup"
echo "========================"
echo "Version: $C2PA_VERSION"
echo "GitHub Org: $GITHUB_ORG"

# Check if library already exists and is valid
if [ -f "${LIBS_DIR}/libc2pa_c.dylib" ]; then
    # Check if library is real (should be > 1MB)
    LIB_SIZE=$(stat -f%z "${LIBS_DIR}/libc2pa_c.dylib" 2>/dev/null || echo 0)
    if [ "$LIB_SIZE" -gt 1000000 ]; then
        echo "✓ libc2pa_c.dylib already exists ($(($LIB_SIZE / 1024 / 1024)) MB)"
        exit 0
    fi
fi

echo "Downloading macOS C2PA libraries..."

# Create directories
mkdir -p "$LIBS_DIR"
mkdir -p "$TEMP_DIR"

# Determine architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    RELEASE_SUFFIX="aarch64-apple-darwin"
    echo "  • Detected Apple Silicon (arm64)"
else
    RELEASE_SUFFIX="x86_64-apple-darwin"
    echo "  • Detected Intel (x86_64)"
fi

# Download the appropriate library
echo "  • Downloading macOS library..."
curl -sL "https://github.com/${GITHUB_ORG}/c2pa-rs/releases/download/c2pa-${C2PA_VERSION}/c2pa-${C2PA_VERSION}-${RELEASE_SUFFIX}.zip" \
    -o "${TEMP_DIR}/macos.zip"

# Extract
echo "  • Extracting library..."
unzip -q -o "${TEMP_DIR}/macos.zip" -d "${TEMP_DIR}/macos"

# Copy library to libs directory
echo "  • Installing library..."
cp "${TEMP_DIR}/macos/lib/libc2pa_c.dylib" "${LIBS_DIR}/"

# Also copy the static library for potential future use
if [ -f "${TEMP_DIR}/macos/lib/libc2pa_c.a" ]; then
    cp "${TEMP_DIR}/macos/lib/libc2pa_c.a" "${LIBS_DIR}/"
fi

# Copy headers
mkdir -p "${SIGNING_SERVER_ROOT}/Sources/C2PAC/include"
cp "${TEMP_DIR}/macos/include/c2pa.h" "${SIGNING_SERVER_ROOT}/Sources/C2PAC/include/c2pa.h.orig"

# Patch the header file for Swift compatibility
echo "  • Patching c2pa.h header..."
sed 's/typedef struct C2paSigner C2paSigner;/typedef struct C2paSigner { } C2paSigner;/g' \
    "${SIGNING_SERVER_ROOT}/Sources/C2PAC/include/c2pa.h.orig" > "${SIGNING_SERVER_ROOT}/Sources/C2PAC/include/c2pa.h"

# Clean up
echo "  • Cleaning up..."
rm -rf "${TEMP_DIR}"

# Verify the library
LIB_SIZE=$(stat -f%z "${LIBS_DIR}/libc2pa_c.dylib")
echo "✓ macOS C2PA library setup completed ($(($LIB_SIZE / 1024 / 1024)) MB)"