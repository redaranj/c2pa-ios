.PHONY: all clean library test-shared test-app example-app publish tests coverage help \
        run-test-app run-example-app signing-server-start signing-server-stop signing-server-status \
        signing-server-build tests-with-server workspace-build quick test-library

# GitHub Release Configuration
GITHUB_ORG := contentauth
C2PA_VERSION := v0.58.0

# Directories
ROOT_DIR := $(shell pwd)
BUILD_DIR := $(ROOT_DIR)/build


# Build configuration
CONFIGURATION := Release
SDK := iphoneos
DESTINATION := platform=iOS Simulator,name=iPhone 16 Pro

# Default target
all: workspace-build


# Build the C2PA library framework
library:
	@echo "Building C2PA library framework..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme Library -configuration $(CONFIGURATION) -destination '$(DESTINATION)' build
	@echo "Library build completed."


# Build entire workspace
workspace-build: library test-shared
	@echo "Building entire workspace..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme TestApp -configuration $(CONFIGURATION) -destination '$(DESTINATION)' build
	@xcodebuild -workspace C2PA.xcworkspace -scheme ExampleApp -configuration $(CONFIGURATION) -destination '$(DESTINATION)' build
	@echo "Workspace build completed."

# Quick build check - builds Library only
quick: library
	@echo "Quick build check completed."

# Build TestShared framework
test-shared: library
	@echo "Building TestShared framework..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme TestShared -configuration $(CONFIGURATION) -destination '$(DESTINATION)' build
	@echo "TestShared build completed."

# Build TestApp
test-app: test-shared
	@echo "Building TestApp..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme TestApp -configuration $(CONFIGURATION) -destination '$(DESTINATION)' build
	@echo "TestApp build completed."

# Build ExampleApp
example-app: library
	@echo "Building ExampleApp..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme ExampleApp -configuration $(CONFIGURATION) -destination '$(DESTINATION)' build
	@echo "ExampleApp build completed."

# Run library tests only
test-library: library
	@echo "Running library unit tests..."
	@xcodebuild test -workspace C2PA.xcworkspace -scheme Library -destination '$(DESTINATION)'
	@echo "Library tests completed."

# Run all tests including unit and UI tests
tests: test-app
	@echo "Running all tests..."
	@xcodebuild test -workspace C2PA.xcworkspace -scheme TestApp -destination '$(DESTINATION)'

# Generate code coverage report
coverage: library
	@echo "Running tests with coverage..."
	@cd Library && swift test --enable-code-coverage
	@echo "Coverage report generated."

# Run test app
run-test-app: test-app
	@echo "Running test app..."
	@xcrun simctl boot "iPhone 16 Pro" || true
	@xcrun simctl install "iPhone 16 Pro" "$(shell xcodebuild -workspace C2PA.xcworkspace -scheme TestApp -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | cut -d '=' -f 2 | xargs)/TestApp.app"
	@xcrun simctl launch "iPhone 16 Pro" org.contentauth.TestApp

# Run example app
run-example-app: example-app
	@echo "Running example app..."
	@xcrun simctl boot "iPhone 16 Pro" || true
	@xcrun simctl install "iPhone 16 Pro" "$(shell xcodebuild -workspace C2PA.xcworkspace -scheme ExampleApp -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | cut -d '=' -f 2 | xargs)/ExampleApp.app"
	@xcrun simctl launch "iPhone 16 Pro" org.contentauth.ExampleApp

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
	
	# Download universal macOS binary for server
	@mkdir -p $(BUILD_DIR)/downloads
	@echo "Downloading macOS universal library..."
	@curl -sL https://github.com/$(GITHUB_ORG)/c2pa-rs/releases/download/c2pa-$(C2PA_VERSION)/c2pa-$(C2PA_VERSION)-universal-apple-darwin.zip -o $(BUILD_DIR)/downloads/macos-universal.zip
	@unzip -q -o $(BUILD_DIR)/downloads/macos-universal.zip -d $(BUILD_DIR)/downloads/macos-universal
	
	# Copy dylib to server
	@cp $(BUILD_DIR)/downloads/macos-universal/lib/libc2pa_c.dylib SigningServer/libs/
	
	# Get header file from macOS download
	@cp $(BUILD_DIR)/downloads/macos-universal/include/c2pa.h SigningServer/Sources/C2PA/include/c2pa.h.orig
	
	# Patch the header file
	@echo "Patching c2pa.h header for server..."
	@sed 's/typedef struct C2paSigner C2paSigner;/typedef struct C2paSigner { } C2paSigner;/g' SigningServer/Sources/C2PA/include/c2pa.h.orig > SigningServer/Sources/C2PA/include/c2pa.h
	@rm -f SigningServer/Sources/C2PA/include/c2pa.h.orig
	
	# Copy Swift files from Library
	@cp Library/Sources/C2PA.swift SigningServer/Sources/C2PA/
	@cp Library/Sources/CertificateManager.swift SigningServer/Sources/C2PA/
	
	# Create module map directly
	@echo 'module C2PAC {' > SigningServer/Sources/C2PA/module.modulemap
	@echo '    header "include/c2pa.h"' >> SigningServer/Sources/C2PA/module.modulemap
	@echo '    export *' >> SigningServer/Sources/C2PA/module.modulemap
	@echo '}' >> SigningServer/Sources/C2PA/module.modulemap
	
	# Copy test certificates
	@cp TestShared/Sources/Resources/es256_certs.pem SigningServer/Resources/
	@cp TestShared/Sources/Resources/es256_private.key SigningServer/Resources/
	
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
	@xcodebuild -workspace C2PA.xcworkspace -scheme Library clean
	@xcodebuild -workspace C2PA.xcworkspace -scheme TestShared clean
	@xcodebuild -workspace C2PA.xcworkspace -scheme TestApp clean
	@xcodebuild -workspace C2PA.xcworkspace -scheme ExampleApp clean
	@rm -rf $(BUILD_DIR)
	@rm -rf SigningServer/.build
	@rm -rf SigningServer/libs
	@rm -rf SigningServer/Sources/C2PA
	@rm -rf SigningServer/Resources
	@echo "Clean complete."

# Help target
help:
	@echo "Available targets:"
	@echo "  make              - Build the library (default)"
	@echo "  make library      - Build the C2PA library framework"
	@echo "  make test-shared  - Build the TestShared framework"
	@echo "  make test-app     - Build the TestApp"
	@echo "  make example-app  - Build the ExampleApp"
	@echo "  make workspace-build - Build entire workspace"
	@echo "  make test-library - Run library unit tests only"
	@echo "  make tests        - Run all tests"
	@echo "  make coverage     - Generate test coverage report"
	@echo "  make run-test-app - Build and run the test app in simulator"
	@echo "  make run-example-app - Build and run the example app in simulator"
	@echo "  make quick        - Quick build check (library only)"
	@echo "  make publish      - Prepare library for publishing"
	@echo "  make signing-server-start - Start the signing server"
	@echo "  make signing-server-stop  - Stop the signing server"
	@echo "  make signing-server-status - Check server status"
	@echo "  make tests-with-server - Run tests with signing server"
	@echo "  make clean        - Clean all build artifacts"
	@echo "  make help         - Show this help message"
