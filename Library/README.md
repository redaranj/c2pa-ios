# C2PA Library

The core C2PA Swift library for iOS, macOS, watchOS, and tvOS.

## Structure

- **Package.swift** - Swift Package Manager manifest
- **Sources/** - Library source code
  - `C2PA/` - Main library implementation
  - `TestShared/` - Shared test utilities
  - `SigningServer/` - Server executable (moved to separate package)
- **Tests/** - Test suites
  - `C2PATests/` - Unit tests
  - `C2PAIntegrationTests/` - Integration tests  
  - `C2PAPerformanceTests/` - Performance tests
- **output/** - Built XCFramework
  - `C2PAC.xcframework` - Binary framework with C2PA native libraries

## Building

```bash
# From the root directory
make library
```

This will:
1. Download the C2PA native libraries
2. Create the XCFramework
3. Build the Swift Package

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(path: "../path/to/c2pa-ios/Library")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Add the Library folder path

## Usage

```swift
import C2PA

// Check if image has C2PA manifest
let hasManifest = try C2PA.hasManifest(data: imageData)

// Sign image with manifest
let signedData = try C2PA.sign(
    data: imageData,
    manifest: manifest,
    signer: signer
)
```

## Testing

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter C2PATests
```