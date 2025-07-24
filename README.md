# C2PA iOS

> [!WARNING]
> **This library is currently in alpha and the API will likely change. Do not use for anything other than early testing.**

[![Tests](https://github.com/contentauth/c2pa-ios/actions/workflows/test.yml/badge.svg)](https://github.com/contentauth/c2pa-ios/actions/workflows/test.yml)

This project provides iOS bindings to the [C2PA](https://c2pa.org/) (Content Authenticity Initiative) libraries. It wraps the C2PA Rust implementation ([c2pa-rs](https://github.com/contentauth/c2pa-rs)) using its C API bindings.

## Overview

C2PA iOS offers:

- iOS/macOS support via Swift Package/XCFramework
- Native Swift APIs for reading, verifying, and signing content with C2PA manifests
- Stream-based APIs for flexible data handling
- Builder APIs for creating custom manifests
- Comprehensive test suite with example application

## Repository Structure

- `/src` - Swift wrapper source code
- `/template` - Swift package template
- `/example` - Example iOS application
- `/output` - Build output artifacts
- `/build` - Temporary build files and external dependencies
- `/Makefile` - Build system commands

## Requirements

### iOS

- iOS 15.0+ / macOS 11.0+
- Xcode 13.0+
- Swift 5.7+

### Development

- Rust (latest stable version)
- Xcode Command Line Tools
- Make

## Installation

### Swift Package Manager

You can add C2PA iOS as a Swift Package Manager dependency:

```swift
dependencies: [
    .package(url: "https://github.com/contentauth/c2pa-ios.git", from: "0.0.1")
]
```

In your target, add the dependency:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: [.product(name: "C2PA", package: "c2pa-ios")]
    )
]
```

### Local Development

For local development without using a released version:

1. Build the iOS framework with `make ios-framework` (or `make ios-dev` for faster Apple Silicon development builds)
2. Add the resulting package in `output/C2PA-iOS` to your project:
   - In Xcode: File ??? Add Package Dependencies ??? Add Local...
   - Navigate to the `output/C2PA-iOS` directory and add it

The Makefile downloads pre-built binaries from GitHub releases, eliminating the need to build the Rust components locally.

## Usage

### Basic File Operations

```swift
import C2PA

// Read C2PA data from a file
do {
    let manifestJSON = try C2PA.readFile(at: imageURL)
    print("C2PA manifest: \(manifestJSON)")
} catch {
    print("Error reading C2PA data: \(error)")
}

// Sign a file with C2PA data
let signerInfo = SignerInfo(
    algorithm: .es256,
    certificatePEM: certificatePEM,
    privateKeyPEM: privateKeyPEM,
    tsaURL: nil
)

let manifestJSON = """
{
    "claim_generator": "MyApp/1.0",
    "title": "Signed Image",
    "format": "image/jpeg"
}
"""

try C2PA.signFile(
    source: inputURL,
    destination: outputURL,
    manifestJSON: manifestJSON,
    signerInfo: signerInfo
)
```

### Stream-Based APIs

```swift
// Create stream from data
let imageData = try Data(contentsOf: imageURL)
let stream = try Stream(data: imageData)

// Read with Reader API
let reader = try Reader(format: "image/jpeg", stream: stream)
let manifestJSON = try reader.json()

// Sign with Builder API
let builder = try Builder(manifestJSON: manifestJSON)
let signer = try Signer(info: signerInfo)

let sourceStream = try Stream(data: imageData)
let destStream = try Stream(fileURL: outputURL)

let manifestData = try builder.sign(
    format: "image/jpeg",
    source: sourceStream,
    destination: destStream,
    signer: signer
)
```

## Building from Source

1. Clone this repository:

   ```bash
   git clone https://github.com/contentauth/c2pa-ios.git
   cd c2pa-ios
   ```

2. Build the iOS framework (downloads pre-built binaries automatically):

   ```bash
   # iOS framework (device + simulator)
   make ios-framework

   # For faster development on Apple Silicon Macs
   make ios-dev          # Only builds for arm64 simulator
   ```

3. Check built outputs:

   ```bash
   # iOS Swift Package
   open output/C2PA-iOS

   # Example App
   open example
   ```

## Makefile Targets

The project includes a comprehensive Makefile with various targets:

- `setup` - Create necessary directories
- `download-binaries` - Download pre-built binaries from GitHub releases
- `ios-framework` - Create iOS XCFramework (default target)
- `ios-dev` - Build iOS library for arm64 simulator only (optimized for Apple Silicon)
- `clean` - Remove build artifacts
- `help` - Show all available targets

The build system downloads pre-built Rust binaries from GitHub releases, eliminating the need for local Rust compilation.

## Example App

The example iOS application in the `example` directory demonstrates comprehensive C2PA functionality:

- **C2PA Library Version** - Display current library version
- **Error Handling** - Proper error handling for invalid files
- **Reading C2PA Data** - Extract manifest data from signed images
- **Stream APIs** - Demonstrate flexible stream-based operations
- **Builder APIs** - Sign images with custom manifest data
- **No-Embed Manifests** - Create cloud/sidecar manifests
- **Resource Management** - Add and extract resources (thumbnails, etc.)
- **Ingredient Support** - Handle ingredient relationships
- **Archive Operations** - Work with C2PA archives
- **Custom Signers** - Implement callback-based signing

The app includes 19 comprehensive tests covering all major C2PA operations. Run the app and tap "Run All Tests" to see the library in action.

## Test Signing Server

For testing certificate enrollment and C2PA signing, a simple Swift-based signing server is included:

```bash
# Start the test server
make server
```

The server runs on `http://localhost:8080` and provides:

- **Certificate Authority**: Signs Certificate Signing Requests (CSRs) for testing
- **C2PA Signing**: Server-side C2PA manifest signing
- **No Authentication**: Simplified for development/testing only

### Key Endpoints

- `GET /health` - Health check
- `POST /api/v1/certificates/sign` - Sign a CSR
- `POST /api/v1/c2pa/sign` - Sign image with C2PA manifest

**⚠️ Testing Only**: This server has no authentication and is intended for development and testing only. For production use, implement proper authentication and security measures.

## License

This project is licensed under the Apache License, Version 2.0 and MIT - see the LICENSE-APACHE and LICENSE-MIT files for details.
