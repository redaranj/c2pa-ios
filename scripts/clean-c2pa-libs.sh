#!/bin/bash

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Directories to clean - following Apple conventions
LIBRARY_DIR="${ROOT_DIR}/Library"
BUILD_DIR="${LIBRARY_DIR}/Build"
OUTPUT_DIR="${LIBRARY_DIR}/output"

# Clean build artifacts
echo "Cleaning C2PA library build artifacts..."

if [ -d "${BUILD_DIR}" ]; then
    echo "Removing ${BUILD_DIR}..."
    rm -rf "${BUILD_DIR}"
fi

if [ -d "${OUTPUT_DIR}" ]; then
    echo "Removing ${OUTPUT_DIR}..."
    rm -rf "${OUTPUT_DIR}"
fi

echo "C2PA library cleanup complete."