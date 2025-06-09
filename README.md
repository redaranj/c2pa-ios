# C2PA Mobile Bindings

This project provides mobile bindings for iOS and Android to the [C2PA](https://c2pa.org/) (Content Authenticity Initiative) libraries. It wraps the C2PA Rust implementation ([c2pa-rs](https://github.com/contentauth/c2pa-rs)) using its C API bindings.

## Overview

C2PA Mobile Bindings offer:

- iOS support via Swift Package/XCFramework
- Android support via AAR library
- Cross-platform APIs for verifying and signing content with C2PA manifests

## Repository Structure

- `/apple` - Swift wrappers and package files for iOS/macOS
  - `/apple/src` - Swift wrapper source code
  - `/apple/template/Package.swift` - Swift package template
  - `/apple/example` - Example iOS application
- `/android` - Android Kotlin wrappers and build files
  - `/android/template` - Android library template with build configuration
  - `/android/src` - Kotlin wrapper source code
  - `/android/example` - Example Android application
- `/output` - Build output artifacts
  - `/output/apple` - Built iOS/macOS frameworks and packages
  - `/output/android/lib` - Built Android AAR library
- `/build` - Temporary build files and external dependencies
- `/Makefile` - Build system commands
- `/.github/workflows` - GitHub Actions for CI/CD

## Requirements

### iOS

- iOS 13.0+ / macOS 11.0+
- Xcode 13.0+
- Swift 5.7+

### Android

- Android API level 21+ (Android 5.0+)
- Android Studio Arctic Fox (2020.3.1) or newer
- JDK 17

### Development

- Rust (latest stable version)
- Cargo with `cross` tool for Android cross-compilation
- Android NDK (for Android builds)
- Android SDK (for Android builds)
- JDK 17 (for Android builds)
- Xcode Command Line Tools (for iOS builds)
- Make

## Installation

### iOS (Swift Package Manager)

You can add C2PA Mobile as a Swift Package Manager dependency:

```swift
dependencies: [
    .package(url: "https://github.com/guardianproject/c2pa-mobile.git", from: "1.0.0")
]
```

In your target, add the dependency:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: [.product(name: "C2PA", package: "c2pa-mobile")]
    )
]
```

#### Development Workflow

For local development without using a released version:

1. Build the iOS framework with `make ios-framework` (or `make ios-dev` for faster Apple Silicon development)
2. Add the resulting package in `output/apple/C2PA-iOS` to your project:
   - In Xcode: File → Add Package Dependencies → Add Local...
   - Navigate to the `output/apple/C2PA-iOS` directory and add it

### Android (Gradle)

You can add C2PA Mobile as a Gradle dependency:

```gradle
dependencies {
    implementation "info.guardianproject:c2pa:1.0.0"
}
```

Make sure to add the GitHub Packages repository to your project:

```gradle
// In your root build.gradle
allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/guardianproject/c2pa-mobile")
            credentials {
                username = System.getenv("GITHUB_USER") ?: project.findProperty("GITHUB_USER")
                password = System.getenv("GITHUB_TOKEN") ?: project.findProperty("GITHUB_TOKEN")
            }
        }
    }
}
```

#### Development Workflow for Android

For local development without using a released version:

1. Build the Android library with `make android-lib android-gradle` (or `make android-dev` for faster emulator development)
2. Add the resulting library in `output/android/lib` to your project as a module:

```gradle
// In settings.gradle
include ':app', ':c2pa'
project(':c2pa').projectDir = new File(rootProject.projectDir, 'path/to/output/android/lib')

// In app/build.gradle
dependencies {
    implementation project(':c2pa')
}
```

## Usage

### iOS Example

```swift
import C2PA

let c2pa = C2PA()

// Verify a file
let result = c2pa.verify(fileURL: URL(fileURLWithPath: "/path/to/file.jpg"))
if result.isValid {
    print("Verification successful: \(result.message)")
} else {
    print("Verification failed: \(result.message)")
}

// Sign a file
let credentials = SigningCredentials(certificate: certificateData, privateKey: privateKeyData)
let signingResult = c2pa.sign(inputURL: URL(fileURLWithPath: "/path/to/input.jpg"), 
                             outputURL: URL(fileURLWithPath: "/path/to/output.jpg"),
                             credentials: credentials)
if signingResult.isSuccess {
    print("Signing successful: \(signingResult.message)")
} else {
    print("Signing failed: \(signingResult.message)")
}
```

### Android Example

```kotlin
import info.guardianproject.c2pa.C2PA

// Initialize C2PA
val c2pa = C2PA()

try {
    // Verify a file
    val isValid = c2pa.verify("/path/to/file.jpg")
    if (isValid) {
        // File has a valid C2PA manifest
        println("Verification successful")
    } else {
        // No valid C2PA manifest found
        println("Verification failed")
    }
    
    // Sign a file
    val success = c2pa.sign(
        "/path/to/input.jpg",
        "/path/to/output.jpg",
        "/path/to/certificate.pem",
        "/path/to/privatekey.pem"
    )
    if (success) {
        println("Signing successful")
    } else {
        println("Signing failed")
    }
} catch (e: C2PA.C2PAException) {
    System.err.println("C2PA error: " + e.message)
}
```

## Building from Source

1. Clone this repository:

   ```bash
   git clone https://github.com/guardianproject/c2pa-mobile.git
   cd c2pa-mobile
   ```

2. Set up the required dependencies:
   - Install Rust: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
   - Install Rust targets:

     ```bash
     rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim
     rustup target add aarch64-linux-android
     ```

   - Install cross: `cargo install cross --git https://github.com/cross-rs/cross`
   - Set up JDK 17 (for Android):

     ```bash
     # macOS with Homebrew:
     brew install openjdk@17
     ```

   - Set up Android SDK
   - Set up environment variables (add to your shell profile):

     ```bash
     export JAVA_HOME=$(/usr/libexec/java_home -v 17)
     export ANDROID_HOME=$HOME/Library/Android/sdk
     ```

3. Clone dependencies:

   ```bash
   make clone-repos
   ```

4. Build for specific platforms:

   ```bash
   # iOS framework
   make ios-framework
   
   # Android library
   make android android-lib android-gradle
   
   # For faster development on Apple Silicon Macs
   make ios-dev          # Only builds for arm64 simulator
   
   # For faster Android development
   make android-dev      # Only builds for x86_64 emulator
   ```

5. Check built outputs:

   ```bash
   # iOS Swift Package
   open output/apple/C2PA-iOS
   
   # Android Library
   open output/android/lib
   
   # Android Example App
   open android/example
   ```

## Makefile Targets

The project includes a comprehensive Makefile with various targets:

- `clone-repos` - Clone required repositories (c2pa-rs and c2pa-c)
- `ios` - Build iOS libraries (device and simulator)
- `ios-framework` - Create iOS XCFramework
- `ios-dev` - Build iOS library for arm64 simulator only (optimized for Apple Silicon)
- `android` - Build Android native libraries for all architectures
- `android-lib` - Package Android Kotlin library
- `android-gradle` - Build Android AAR file
- `android-dev` - Build Android library only for emulator (faster development)
- `clean` - Remove build artifacts
- `help` - Show all available targets

## Continuous Integration & Releases

This project uses GitHub Actions for continuous integration and release management:

### Release Process

1. **Start a Release**:
   - Trigger the "Start Release Process" workflow from the Actions tab
   - Enter the version number (e.g., `v1.0.0`)
   - This kicks off the build-apple workflow

2. **Apple Build**:
   - Builds the XCFramework for iOS
   - Updates `Package.swift` with the release URL and checksum
   - Creates a tag for the release
   - Triggers the Android build

3. **Android Build**:
   - Can be manually triggered for testing/debugging
   - Builds the AAR package for Android
   - Archives the Android artifacts
   - Triggers the finish-release workflow

4. **Finish Release**:
   - Creates a GitHub release with the specified version
   - Attaches all built artifacts (iOS framework, Swift package, Android AAR)
   - Publishes documentation for integration

### Manual Testing

The Android build workflow can be manually triggered from GitHub Actions for debugging and testing purposes.

## Example Apps

For examples of how to use these libraries, see:

- **iOS:** The example app in `apple/example` shows integration with iOS apps.
- **Android:** The example app in `android/example` demonstrates integration with Android apps.

## JNI Implementation

The Android library uses JNI (Java Native Interface) to connect the Kotlin wrapper to the C2PA C library:

- C API headers are in `android/template/c2pa/src/main/cpp/include/c2pa.h`
- JNI implementation is in `android/template/c2pa/src/main/cpp/c2pa_jni.cpp`
- Kotlin wrapper is in `android/src/c2pa.kt`

## License

This project is licensed under the Apache License, Version 2.0 and MIT - see the LICENSE-APACHE and LICENSE-MIT files for details.