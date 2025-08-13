.PHONY: all clean setup download-binaries library publish tests coverage help run-test-app run-example-app \
        signing-server-start signing-server-stop signing-server-status signing-server-build \
        tests-with-server workspace-build xcframework

# GitHub Release Configuration
GITHUB_ORG := contentauth
C2PA_VERSION := v0.58.0

# Directories
ROOT_DIR := $(shell pwd)
BUILD_DIR := $(ROOT_DIR)/build
DOWNLOAD_DIR := $(BUILD_DIR)/downloads
OUTPUT_DIR := $(ROOT_DIR)/Library/output

# Apple targets
IOS_FRAMEWORK_NAME := C2PAC
IOS_XCFRAMEWORK_PATH := $(OUTPUT_DIR)/$(IOS_FRAMEWORK_NAME).xcframework

# iOS architectures
IOS_ARCHS := arm64 x86_64 arm64-simulator
IOS_ARM64_TARGET := aarch64-apple-ios
IOS_X86_64_TARGET := x86_64-apple-ios
IOS_ARM64_SIM_TARGET := aarch64-apple-ios-sim

# Build configuration
CONFIGURATION := Release
SDK := iphoneos
DESTINATION := platform=iOS Simulator,name=iPhone 15

# Default target
all: library

# Setup directories
setup:
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(DOWNLOAD_DIR)
	@mkdir -p $(OUTPUT_DIR)
	@mkdir -p $(BUILD_DIR)/ios/arm64/lib
	@mkdir -p $(BUILD_DIR)/ios/x86_64/lib
	@mkdir -p $(BUILD_DIR)/ios/arm64-simulator/lib
	@mkdir -p $(BUILD_DIR)/patched_headers

# Function to download and extract a pre-built library
# Args: 1=architecture name for display, 2=release filename suffix, 3=target directory name
define download_library
	@echo "Downloading iOS $(1) library..."
	@curl -sL https://github.com/$(GITHUB_ORG)/c2pa-rs/releases/download/c2pa-$(C2PA_VERSION)/c2pa-$(C2PA_VERSION)-$(2).zip -o $(DOWNLOAD_DIR)/$(3).zip
	@unzip -q -o $(DOWNLOAD_DIR)/$(3).zip -d $(DOWNLOAD_DIR)/$(3)
	@cp $(DOWNLOAD_DIR)/$(3)/lib/libc2pa_c.a $(BUILD_DIR)/ios/$(3)/lib/
	$(if $(4),@cp $(DOWNLOAD_DIR)/$(3)/include/c2pa.h $(BUILD_DIR)/patched_headers/c2pa.h.orig)
endef

# Function to download macOS library (for server)
# Args: 1=architecture name for display, 2=release filename suffix, 3=target directory name
define download_macos_library
	@echo "Downloading macOS $(1) library..."
	@curl -sL https://github.com/$(GITHUB_ORG)/c2pa-rs/releases/download/c2pa-$(C2PA_VERSION)/c2pa-$(C2PA_VERSION)-$(2).zip -o $(DOWNLOAD_DIR)/$(3).zip
	@unzip -q -o $(DOWNLOAD_DIR)/$(3).zip -d $(DOWNLOAD_DIR)/$(3)
endef

# Download pre-built binaries from GitHub releases
download-binaries: setup
	@echo "Downloading pre-built binaries from $(GITHUB_ORG)/c2pa-rs release c2pa-$(C2PA_VERSION)..."
	
	# Download all iOS libraries
	$(call download_library,arm64,aarch64-apple-ios,arm64,true)
	$(call download_library,x86_64 simulator,x86_64-apple-ios,x86_64)
	$(call download_library,arm64 simulator,aarch64-apple-ios-sim,arm64-simulator)
	
	# Patch the header file
	@echo "Patching c2pa.h header..."
	@sed 's/typedef struct C2paSigner C2paSigner;/typedef struct C2paSigner { } C2paSigner;/g' $(BUILD_DIR)/patched_headers/c2pa.h.orig > $(BUILD_DIR)/patched_headers/c2pa.h
	@rm -f $(BUILD_DIR)/patched_headers/c2pa.h.orig
	
	@echo "Pre-built binaries downloaded successfully."

# Complete library build: setup, download binaries, and build framework
library: setup download-binaries xcframework
	@echo "Building library Swift package..."
	@cd Library && swift build -c release
	@echo "Library build completed."

xcframework: download-binaries
	@echo "Creating XCFramework..."
	@mkdir -p $(OUTPUT_DIR)

	# Create device library
	@mkdir -p $(BUILD_DIR)/ios/device/lib
	@cp $(BUILD_DIR)/ios/arm64/lib/libc2pa_c.a $(BUILD_DIR)/ios/device/lib/

	# Create simulator fat library
	@mkdir -p $(BUILD_DIR)/ios/simulator/lib
	@lipo -create \
		$(BUILD_DIR)/ios/x86_64/lib/libc2pa_c.a \
		$(BUILD_DIR)/ios/arm64-simulator/lib/libc2pa_c.a \
		-output $(BUILD_DIR)/ios/simulator/lib/libc2pa_c.a

	# First, make sure the output directory doesn't exist (to avoid conflicts)
	@rm -rf $(IOS_XCFRAMEWORK_PATH)

	# Create XCFramework
	xcodebuild -create-xcframework \
		-library $(BUILD_DIR)/ios/device/lib/libc2pa_c.a \
		-headers $(BUILD_DIR)/patched_headers \
		-library $(BUILD_DIR)/ios/simulator/lib/libc2pa_c.a \
		-headers $(BUILD_DIR)/patched_headers \
		-output $(IOS_XCFRAMEWORK_PATH)

	# Create module map for the XCFramework
	@echo 'module C2PAC {' > $(BUILD_DIR)/module.modulemap
	@echo '    header "c2pa.h"' >> $(BUILD_DIR)/module.modulemap
	@echo '    export *' >> $(BUILD_DIR)/module.modulemap
	@echo '}' >> $(BUILD_DIR)/module.modulemap

	# Copy module map to each platform in XCFramework
	# For static libraries, we need to create the module map in Headers directory
	@cp $(BUILD_DIR)/module.modulemap $(IOS_XCFRAMEWORK_PATH)/ios-arm64/Headers/module.modulemap || true
	@cp $(BUILD_DIR)/module.modulemap $(IOS_XCFRAMEWORK_PATH)/ios-arm64_x86_64-simulator/Headers/module.modulemap || true

	@echo "XCFramework created successfully at $(IOS_XCFRAMEWORK_PATH)"

# Build iOS development version (arm64 simulator only - optimized for Apple Silicon Macs)
ios-dev: setup
	@echo "Building iOS development version (arm64 simulator only)..."
	
	# Download only the arm64 simulator library
	$(call download_library,arm64 simulator,aarch64-apple-ios-sim,arm64-simulator,true)
	
	# Patch the header file
	@echo "Patching c2pa.h header..."
	@sed 's/typedef struct C2paSigner C2paSigner;/typedef struct C2paSigner { } C2paSigner;/g' $(BUILD_DIR)/patched_headers/c2pa.h.orig > $(BUILD_DIR)/patched_headers/c2pa.h
	
	# Create simulator directory
	@mkdir -p $(BUILD_DIR)/ios/simulator/lib
	@cp $(BUILD_DIR)/ios/arm64-simulator/lib/libc2pa_c.a $(BUILD_DIR)/ios/simulator/lib/
	
	# Create XCFramework with only arm64 simulator
	@rm -rf $(IOS_XCFRAMEWORK_PATH)
	xcodebuild -create-xcframework \
		-library $(BUILD_DIR)/ios/simulator/lib/libc2pa_c.a \
		-headers $(BUILD_DIR)/patched_headers \
		-output $(IOS_XCFRAMEWORK_PATH)
	
	# Create module map
	@echo 'module C2PAC {' > $(BUILD_DIR)/module.modulemap
	@echo '    header "c2pa.h"' >> $(BUILD_DIR)/module.modulemap
	@echo '    export *' >> $(BUILD_DIR)/module.modulemap
	@echo '}' >> $(BUILD_DIR)/module.modulemap
	
	# Copy module map to XCFramework
	@cp $(BUILD_DIR)/module.modulemap $(IOS_XCFRAMEWORK_PATH)/ios-arm64-simulator/C2PAC.framework/Modules/module.modulemap
	
	@echo "iOS development build complete (arm64 simulator only)"

# Build entire workspace
workspace-build: library
	@echo "Building workspace..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme TestApp -configuration $(CONFIGURATION) build
	@xcodebuild -workspace C2PA.xcworkspace -scheme ExampleApp -configuration $(CONFIGURATION) build
	@echo "Workspace build completed."

# Run all tests including unit and UI tests
tests: library
	@echo "Running library unit tests..."
	@cd Library && swift test
	@echo "Running test app UI tests..."
	@xcodebuild test -workspace C2PA.xcworkspace -scheme TestApp -destination '$(DESTINATION)'

# Generate code coverage report
coverage: library
	@echo "Running tests with coverage..."
	@cd Library && swift test --enable-code-coverage
	@echo "Coverage report generated."

# Run test app
run-test-app: library
	@echo "Building and running test app..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme TestApp -configuration Debug -destination '$(DESTINATION)' -derivedDataPath $(BUILD_DIR)/DerivedData build
	@xcrun simctl boot "iPhone 15" || true
	@xcrun simctl install "iPhone 15" "$(BUILD_DIR)/DerivedData/Build/Products/Debug-iphonesimulator/TestApp.app"
	@xcrun simctl launch "iPhone 15" org.contentauth.c2pa.testapp

# Run example app
run-example-app: library
	@echo "Building and running example app..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme ExampleApp -configuration Debug -destination '$(DESTINATION)' -derivedDataPath $(BUILD_DIR)/DerivedData build
	@xcrun simctl boot "iPhone 15" || true
	@xcrun simctl install "iPhone 15" "$(BUILD_DIR)/DerivedData/Build/Products/Debug-iphonesimulator/ExampleApp.app"
	@xcrun simctl launch "iPhone 15" org.contentauth.c2pa.exampleapp

# Publish library to GitHub packages or CocoaPods
publish: library
	@echo "Publishing library..."
	@cd Library && swift package update
	@echo "Ready to publish. Add pod push or GitHub release commands here."

# Tests with signing server
tests-with-server: signing-server-start tests signing-server-stop
	@echo "Tests with server completed."

# Setup local test server with signing capabilities
signing-server-build:
	@echo "Setting up C2PA signing server..."
	@command -v swift >/dev/null 2>&1 || { echo "Error: Swift is required but not installed."; exit 1; }
	
	# Create server directories
	@mkdir -p SigningServer/libs
	@mkdir -p SigningServer/Sources/C2PA/include
	@mkdir -p SigningServer/Resources
	
	# Download universal macOS binary
	$(call download_macos_library,universal,universal-apple-darwin,macos-universal)
	
	# Copy dylib to server
	@cp $(DOWNLOAD_DIR)/macos-universal/lib/libc2pa_c.dylib SigningServer/libs/
	
	# Get header file from macOS download
	@cp $(DOWNLOAD_DIR)/macos-universal/include/c2pa.h SigningServer/Sources/C2PA/include/c2pa.h.orig
	
	# Patch the header file
	@echo "Patching c2pa.h header for server..."
	@sed 's/typedef struct C2paSigner C2paSigner;/typedef struct C2paSigner { } C2paSigner;/g' SigningServer/Sources/C2PA/include/c2pa.h.orig > SigningServer/Sources/C2PA/include/c2pa.h
	@rm -f SigningServer/Sources/C2PA/include/c2pa.h.orig
	
	# Copy Swift files and module map
	@cp Library/Sources/C2PA.swift SigningServer/Sources/C2PA/
	@cp Library/Sources/CertificateManager.swift SigningServer/Sources/C2PA/
	@cp template/module.modulemap SigningServer/Sources/C2PA/
	# Update header path in module map for server structure
	@sed -i '' 's|header "c2pa.h"|header "include/c2pa.h"|' SigningServer/Sources/C2PA/module.modulemap
	
	# Copy test certificates
	@cp Library/Tests/Resources/es256_certs.pem SigningServer/Resources/
	@cp Library/Tests/Resources/es256_private.key SigningServer/Resources/
	
	@cd SigningServer && swift package resolve
	@echo "Server setup complete!"

signing-server-start: signing-server-build
	@echo "Building server..."
	@cd SigningServer && swift build
	@echo "Starting signing server..."
	@cd SigningServer && swift run SigningServer > ../signing-server.log 2>&1 &
	@echo "Signing server started. Check signing-server.log for details."
	@echo "Server running at http://localhost:8080"
	@echo "Server is now running. Use 'make signing-server-stop' to stop it."

# Stop the signing server  
signing-server-stop:
	@echo "Stopping signing server..."
	@pkill -f "SigningServer" || true
	@pkill -f ".build/debug/SigningServer" || true
	@echo "Server stopped."

# Check signing server status
signing-server-status:
	@echo "Checking signing server status..."
	@ps aux | grep -v grep | grep "SigningServer" || echo "Server is not running"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@rm -rf $(OUTPUT_DIR)
	@rm -rf Library/.build
	@rm -rf TestApp/build
	@rm -rf ExampleApp/build
	@rm -rf SigningServer/.build
	@rm -rf SigningServer/libs
	@rm -rf SigningServer/Sources/C2PA
	@rm -rf SigningServer/Resources
	@echo "Clean complete."

# Help target
help:
	@echo "Available targets:"
	@echo "  make              - Build the library (default)"
	@echo "  make library      - Build the C2PA library and framework"
	@echo "  make tests        - Run all tests"
	@echo "  make coverage     - Generate test coverage report"
	@echo "  make run-test-app - Build and run the test app in simulator"
	@echo "  make run-example-app - Build and run the example app in simulator"
	@echo "  make workspace-build - Build entire workspace"
	@echo "  make ios-dev      - Build for development (arm64 simulator only)"
	@echo "  make publish      - Prepare library for publishing"
	@echo "  make signing-server-start - Start the signing server"
	@echo "  make signing-server-stop  - Stop the signing server"
	@echo "  make signing-server-status - Check server status"
	@echo "  make tests-with-server - Run tests with signing server"
	@echo "  make clean        - Clean all build artifacts"
	@echo "  make help         - Show this help message"