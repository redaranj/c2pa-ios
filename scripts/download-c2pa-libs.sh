#!/bin/bash
set -e

# This script downloads and sets up the C2PA libraries
# It's designed to be run from make before xcodebuild

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FRAMEWORKS_DIR="${PROJECT_ROOT}/Library/Frameworks"
BUILD_DIR="${PROJECT_ROOT}/Library/Build"

# Read configuration
XCCONFIG_FILE="${PROJECT_ROOT}/Configurations/Base.xcconfig"
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

echo "C2PA Library Setup"
echo "=================="
echo "Version: $C2PA_VERSION"
echo "GitHub Org: $GITHUB_ORG"

# Check if real framework already exists
if [ -f "${FRAMEWORKS_DIR}/C2PAC.xcframework/ios-arm64/libc2pa_c.a" ] && \
   [ -f "${FRAMEWORKS_DIR}/C2PAC.xcframework/ios-arm64_x86_64-simulator/libc2pa_c.a" ]; then
    # Check if libraries are real (should be > 1MB)
    ARM64_SIZE=$(stat -f%z "${FRAMEWORKS_DIR}/C2PAC.xcframework/ios-arm64/libc2pa_c.a" 2>/dev/null || echo 0)
    if [ "$ARM64_SIZE" -gt 1000000 ]; then
        echo "✓ C2PAC.xcframework already exists with real libraries"
        exit 0
    fi
fi

echo "Downloading C2PA libraries..."

# Setup directories
DOWNLOAD_DIR="${BUILD_DIR}/Downloads"
mkdir -p "${BUILD_DIR}"
mkdir -p "${DOWNLOAD_DIR}"
mkdir -p "${FRAMEWORKS_DIR}"
mkdir -p "${BUILD_DIR}/ios/arm64/lib"
mkdir -p "${BUILD_DIR}/ios/x86_64/lib"
mkdir -p "${BUILD_DIR}/ios/arm64-simulator/lib"
mkdir -p "${BUILD_DIR}/patched_headers"

# Download function
download_library() {
    local arch_display="$1"
    local release_suffix="$2"
    local target_dir="$3"
    local copy_header="$4"
    
    echo "  • Downloading iOS ${arch_display} library..."
    curl -sL "https://github.com/${GITHUB_ORG}/c2pa-rs/releases/download/c2pa-${C2PA_VERSION}/c2pa-${C2PA_VERSION}-${release_suffix}.zip" \
        -o "${DOWNLOAD_DIR}/${target_dir}.zip"
    
    unzip -q -o "${DOWNLOAD_DIR}/${target_dir}.zip" -d "${DOWNLOAD_DIR}/${target_dir}"
    cp "${DOWNLOAD_DIR}/${target_dir}/lib/libc2pa_c.a" "${BUILD_DIR}/ios/${target_dir}/lib/"
    
    if [ "$copy_header" = "true" ]; then
        cp "${DOWNLOAD_DIR}/${target_dir}/include/c2pa.h" "${BUILD_DIR}/patched_headers/c2pa.h.orig"
    fi
}

# Download all iOS libraries
download_library "arm64" "aarch64-apple-ios" "arm64" "true"
download_library "x86_64 simulator" "x86_64-apple-ios" "x86_64"
download_library "arm64 simulator" "aarch64-apple-ios-sim" "arm64-simulator"

# Patch the header file
echo "  • Patching c2pa.h header..."
sed 's/typedef struct C2paSigner C2paSigner;/typedef struct C2paSigner { } C2paSigner;/g' \
    "${BUILD_DIR}/patched_headers/c2pa.h.orig" > "${BUILD_DIR}/patched_headers/c2pa.h"

# Create device library
mkdir -p "${BUILD_DIR}/ios/device/lib"
cp "${BUILD_DIR}/ios/arm64/lib/libc2pa_c.a" "${BUILD_DIR}/ios/device/lib/"

# Create simulator fat library
echo "  • Creating universal simulator library..."
mkdir -p "${BUILD_DIR}/ios/simulator/lib"
lipo -create \
    "${BUILD_DIR}/ios/x86_64/lib/libc2pa_c.a" \
    "${BUILD_DIR}/ios/arm64-simulator/lib/libc2pa_c.a" \
    -output "${BUILD_DIR}/ios/simulator/lib/libc2pa_c.a"

# Remove existing XCFramework if it exists
if [ -d "${FRAMEWORKS_DIR}/C2PAC.xcframework" ]; then
    echo "  • Removing existing framework..."
    rm -rf "${FRAMEWORKS_DIR}/C2PAC.xcframework"
fi

# Create XCFramework
echo "  • Creating XCFramework..."
xcodebuild -create-xcframework \
    -library "${BUILD_DIR}/ios/device/lib/libc2pa_c.a" \
    -headers "${BUILD_DIR}/patched_headers" \
    -library "${BUILD_DIR}/ios/simulator/lib/libc2pa_c.a" \
    -headers "${BUILD_DIR}/patched_headers" \
    -output "${FRAMEWORKS_DIR}/C2PAC.xcframework"

# Add module maps to XCFramework
cat > "${FRAMEWORKS_DIR}/C2PAC.xcframework/ios-arm64/Headers/module.modulemap" << EOF
module C2PAC {
    header "c2pa.h"
    export *
}
EOF

cat > "${FRAMEWORKS_DIR}/C2PAC.xcframework/ios-arm64_x86_64-simulator/Headers/module.modulemap" << EOF
module C2PAC {
    header "c2pa.h"
    export *
}
EOF

echo "✓ C2PA library setup completed successfully"