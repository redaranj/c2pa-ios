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
# SigningServer artifacts go in its own Build directory
SERVER_DIR="${ROOT_DIR}/SigningServer"
BUILD_DIR="${SERVER_DIR}/Build"
DOWNLOAD_DIR="${BUILD_DIR}/Downloads"

# Setup signing server with macOS library
setup_signing_server() {
    echo "Setting up C2PA signing server..."
    
    # Check for Swift
    if ! command -v swift &> /dev/null; then
        echo "Error: Swift is required but not installed."
        exit 1
    fi
    
    # Create server directories
    mkdir -p "${SERVER_DIR}/libs"
    mkdir -p "${SERVER_DIR}/Sources/C2PA/include"
    mkdir -p "${SERVER_DIR}/Resources"
    mkdir -p "${DOWNLOAD_DIR}"
    
    # Download universal macOS binary
    echo "Downloading macOS universal library..."
    curl -sL "https://github.com/${GITHUB_ORG}/c2pa-rs/releases/download/c2pa-${C2PA_VERSION}/c2pa-${C2PA_VERSION}-universal-apple-darwin.zip" \
        -o "${DOWNLOAD_DIR}/macos-universal.zip"
    
    unzip -q -o "${DOWNLOAD_DIR}/macos-universal.zip" -d "${DOWNLOAD_DIR}/macos-universal"
    
    # Copy dylib to server
    cp "${DOWNLOAD_DIR}/macos-universal/lib/libc2pa_c.dylib" "${SERVER_DIR}/libs/"
    
    # Get header file from macOS download
    cp "${DOWNLOAD_DIR}/macos-universal/include/c2pa.h" "${SERVER_DIR}/Sources/C2PA/include/c2pa.h.orig"
    
    # Patch the header file
    echo "Patching c2pa.h header for server..."
    sed 's/typedef struct C2paSigner C2paSigner;/typedef struct C2paSigner { } C2paSigner;/g' \
        "${SERVER_DIR}/Sources/C2PA/include/c2pa.h.orig" > "${SERVER_DIR}/Sources/C2PA/include/c2pa.h"
    
    # Copy Swift files from Library
    if [ -f "${ROOT_DIR}/Library/Sources/C2PA/C2PA.swift" ]; then
        cp "${ROOT_DIR}/Library/Sources/C2PA/C2PA.swift" "${SERVER_DIR}/Sources/C2PA/"
    fi
    
    if [ -f "${ROOT_DIR}/Library/Sources/C2PA/CertificateManager.swift" ]; then
        cp "${ROOT_DIR}/Library/Sources/C2PA/CertificateManager.swift" "${SERVER_DIR}/Sources/C2PA/"
    fi
    
    # Create module map for server
    cat > "${SERVER_DIR}/Sources/C2PA/module.modulemap" << 'EOF'
module C2PAC {
    header "include/c2pa.h"
    export *
}
EOF
    
    # Copy test certificates if they exist
    if [ -f "${ROOT_DIR}/Library/Tests/C2PATests/Resources/es256_certs.pem" ]; then
        cp "${ROOT_DIR}/Library/Tests/C2PATests/Resources/es256_certs.pem" "${SERVER_DIR}/Resources/"
    fi
    
    if [ -f "${ROOT_DIR}/Library/Tests/C2PATests/Resources/es256_private.key" ]; then
        cp "${ROOT_DIR}/Library/Tests/C2PATests/Resources/es256_private.key" "${SERVER_DIR}/Resources/"
    fi
    
    echo "Resolving Swift package dependencies..."
    cd "${SERVER_DIR}" && swift package resolve
    
    echo "Server setup complete!"
    echo ""
    echo "To build the server: cd SigningServer && swift build"
    echo "To run the server: cd SigningServer && swift run Run"
}

# Main execution
setup_signing_server