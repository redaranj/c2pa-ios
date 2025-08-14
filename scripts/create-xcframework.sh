#!/bin/bash
set -e

# Create C2PA.xcframework from built frameworks for distribution
# This script combines device and simulator builds into a single xcframework

echo "Creating C2PA.xcframework for distribution..."

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DERIVED_DATA_BASE="${HOME}/Library/Developer/Xcode/DerivedData"
WORKSPACE_NAME="C2PA"
OUTPUT_DIR="${PROJECT_ROOT}/output"

# Find the DerivedData folder
DERIVED_DATA_PATH=$(ls -d ${DERIVED_DATA_BASE}/${WORKSPACE_NAME}-* 2>/dev/null | head -n1)
if [ -z "$DERIVED_DATA_PATH" ]; then
    DERIVED_DATA_PATH="${DERIVED_DATA_BASE}/${WORKSPACE_NAME}-generated"
fi

# Framework paths
DEVICE_FRAMEWORK="${DERIVED_DATA_PATH}/Build/Products/Release-iphoneos/C2PA.framework"
SIMULATOR_FRAMEWORK="${DERIVED_DATA_PATH}/Build/Products/Release-iphonesimulator/C2PA.framework"

# Check if frameworks exist
if [ ! -d "$DEVICE_FRAMEWORK" ]; then
    echo "Error: Device framework not found at $DEVICE_FRAMEWORK"
    echo "Please run 'make library' first to build the frameworks"
    exit 1
fi

if [ ! -d "$SIMULATOR_FRAMEWORK" ]; then
    echo "Error: Simulator framework not found at $SIMULATOR_FRAMEWORK"
    echo "Please run 'make library' first to build the frameworks"
    exit 1
fi

# Create output directory
echo "Creating output directory..."
mkdir -p "$OUTPUT_DIR"

# Remove existing xcframework if it exists
if [ -d "$OUTPUT_DIR/C2PA.xcframework" ]; then
    echo "Removing existing C2PA.xcframework..."
    rm -rf "$OUTPUT_DIR/C2PA.xcframework"
fi

# Create xcframework
echo "Creating xcframework..."
xcodebuild -create-xcframework \
    -framework "$DEVICE_FRAMEWORK" \
    -framework "$SIMULATOR_FRAMEWORK" \
    -output "$OUTPUT_DIR/C2PA.xcframework"

# Verify creation
if [ -d "$OUTPUT_DIR/C2PA.xcframework" ]; then
    echo "✅ C2PA.xcframework created successfully at: $OUTPUT_DIR/C2PA.xcframework"
    echo ""
    echo "The framework is now ready for distribution via Swift Package Manager."
    echo "Users can add the package using the root Package.swift file."
else
    echo "❌ Failed to create C2PA.xcframework"
    exit 1
fi