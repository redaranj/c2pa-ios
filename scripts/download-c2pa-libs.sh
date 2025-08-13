#!/bin/bash

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Read configuration from xcconfig
XCCONFIG_FILE="${ROOT_DIR}/Configurations/Base.xcconfig"
if [ ! -f "$XCCONFIG_FILE" ]; then
    echo "Error: Base.xcconfig not found at $XCCONFIG_FILE"
    exit 1
fi

# Extract values from xcconfig
GITHUB_ORG=$(grep "^GITHUB_ORG" "$XCCONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
C2PA_VERSION=$(grep "^C2PA_VERSION" "$XCCONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')

if [ -z "$GITHUB_ORG" ] || [ -z "$C2PA_VERSION" ]; then
    echo "Error: Could not read GITHUB_ORG or C2PA_VERSION from $XCCONFIG_FILE"
    exit 1
fi

echo "Using configuration: GITHUB_ORG=$GITHUB_ORG, C2PA_VERSION=$C2PA_VERSION"

# Directories - following Apple conventions
# Intermediate build files go in Library/Build
# Downloaded artifacts go in Library/Build/Downloads
# Final XCFramework output stays in Library/output (visible to other projects)
LIBRARY_DIR="${ROOT_DIR}/Library"
BUILD_DIR="${LIBRARY_DIR}/Build"
DOWNLOAD_DIR="${BUILD_DIR}/Downloads"
OUTPUT_DIR="${LIBRARY_DIR}/output"

# Setup directories
setup_directories() {
    mkdir -p "${BUILD_DIR}"
    mkdir -p "${DOWNLOAD_DIR}"
    mkdir -p "${OUTPUT_DIR}"
    mkdir -p "${BUILD_DIR}/ios/arm64/lib"
    mkdir -p "${BUILD_DIR}/ios/x86_64/lib"
    mkdir -p "${BUILD_DIR}/ios/arm64-simulator/lib"
    mkdir -p "${BUILD_DIR}/patched_headers"
}

# Download and extract a pre-built library
download_library() {
    local arch_display="$1"
    local release_suffix="$2"
    local target_dir="$3"
    local copy_header="$4"
    
    echo "Downloading iOS ${arch_display} library..."
    curl -sL "https://github.com/${GITHUB_ORG}/c2pa-rs/releases/download/c2pa-${C2PA_VERSION}/c2pa-${C2PA_VERSION}-${release_suffix}.zip" \
        -o "${DOWNLOAD_DIR}/${target_dir}.zip"
    
    unzip -q -o "${DOWNLOAD_DIR}/${target_dir}.zip" -d "${DOWNLOAD_DIR}/${target_dir}"
    cp "${DOWNLOAD_DIR}/${target_dir}/lib/libc2pa_c.a" "${BUILD_DIR}/ios/${target_dir}/lib/"
    
    if [ "$copy_header" = "true" ]; then
        cp "${DOWNLOAD_DIR}/${target_dir}/include/c2pa.h" "${BUILD_DIR}/patched_headers/c2pa.h.orig"
    fi
}

# Create XCFramework
create_xcframework() {
    echo "Creating XCFramework..."
    mkdir -p "${OUTPUT_DIR}"
    
    # Create device library
    mkdir -p "${BUILD_DIR}/ios/device/lib"
    cp "${BUILD_DIR}/ios/arm64/lib/libc2pa_c.a" "${BUILD_DIR}/ios/device/lib/"
    
    # Create simulator fat library
    mkdir -p "${BUILD_DIR}/ios/simulator/lib"
    lipo -create \
        "${BUILD_DIR}/ios/x86_64/lib/libc2pa_c.a" \
        "${BUILD_DIR}/ios/arm64-simulator/lib/libc2pa_c.a" \
        -output "${BUILD_DIR}/ios/simulator/lib/libc2pa_c.a"
    
    # Remove existing XCFramework if it exists
    rm -rf "${OUTPUT_DIR}/C2PAC.xcframework"
    
    # Create XCFramework
    xcodebuild -create-xcframework \
        -library "${BUILD_DIR}/ios/device/lib/libc2pa_c.a" \
        -headers "${BUILD_DIR}/patched_headers" \
        -library "${BUILD_DIR}/ios/simulator/lib/libc2pa_c.a" \
        -headers "${BUILD_DIR}/patched_headers" \
        -output "${OUTPUT_DIR}/C2PAC.xcframework"
    
    # Create module map
    cat > "${BUILD_DIR}/module.modulemap" << EOF
module C2PAC {
    header "c2pa.h"
    export *
}
EOF
    
    # Copy module map to each platform in XCFramework
    cp "${BUILD_DIR}/module.modulemap" "${OUTPUT_DIR}/C2PAC.xcframework/ios-arm64/Headers/module.modulemap" 2>/dev/null || true
    cp "${BUILD_DIR}/module.modulemap" "${OUTPUT_DIR}/C2PAC.xcframework/ios-arm64_x86_64-simulator/Headers/module.modulemap" 2>/dev/null || true
    
    echo "XCFramework created successfully at ${OUTPUT_DIR}/C2PAC.xcframework"
}

# Main execution
main() {
    echo "Starting C2PA library download and setup..."
    
    setup_directories
    
    echo "Downloading pre-built binaries from ${GITHUB_ORG}/c2pa-rs release c2pa-${C2PA_VERSION}..."
    
    # Download all iOS libraries
    download_library "arm64" "aarch64-apple-ios" "arm64" "true"
    download_library "x86_64 simulator" "x86_64-apple-ios" "x86_64"
    download_library "arm64 simulator" "aarch64-apple-ios-sim" "arm64-simulator"
    
    # Patch the header file
    echo "Patching c2pa.h header..."
    sed 's/typedef struct C2paSigner C2paSigner;/typedef struct C2paSigner { } C2paSigner;/g' \
        "${BUILD_DIR}/patched_headers/c2pa.h.orig" > "${BUILD_DIR}/patched_headers/c2pa.h"
    
    create_xcframework
    
    echo "C2PA library setup completed successfully."
}

# Run main function
main "$@"