.PHONY: all clean build test run-tests run-example run-testapp help \
        workspace library signing-server testshared download-libs

# Configuration
CONFIGURATION := Release
DEBUG_CONFIGURATION := Debug

# Detect architecture
ARCH := $(shell uname -m)
ifeq ($(ARCH),arm64)
    SIM_ARCH := arm64
else
    SIM_ARCH := x86_64
endif

# Simulator settings - using generic destination to let Xcode pick appropriate simulator
# Use a specific device ID or name for more reliable builds
SIMULATOR_DESTINATION := platform=iOS Simulator,id=4AC016CA-3FE0-4C21-8F98-0BED14CF8138

# DerivedData path - can be overridden with environment variable
# Use a consistent location based on workspace name
WORKSPACE_NAME := C2PA
DERIVED_DATA_BASE := $(HOME)/Library/Developer/Xcode/DerivedData
# Find the actual DerivedData folder for this workspace
DERIVED_DATA_PATH := $(shell ls -d $(DERIVED_DATA_BASE)/$(WORKSPACE_NAME)-* 2>/dev/null | head -n1)
ifeq ($(DERIVED_DATA_PATH),)
    # If no existing DerivedData, use a predictable name
    DERIVED_DATA_PATH := $(DERIVED_DATA_BASE)/$(WORKSPACE_NAME)-generated
endif

# Default target
all: build

# Build the entire workspace - library first, then TestShared, then TestApp
build: library testshared testapp

# Build the workspace with all targets
workspace:
	@echo "Building C2PA workspace..."
	xcodebuild -workspace C2PA.xcworkspace \
		-scheme "Library" \
		-configuration $(CONFIGURATION) \
		-destination "generic/platform=iOS" \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		build
	@echo "Workspace build completed."

# Build TestApp
testapp: library testshared
	@echo "Building TestApp..."
	xcodebuild -workspace C2PA.xcworkspace \
		-scheme "TestApp" \
		-configuration $(DEBUG_CONFIGURATION) \
		-destination '$(SIMULATOR_DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		build
	@echo "TestApp build completed."

# Download C2PA libraries
download-libs:
	@echo "Setting up C2PA libraries..."
	@scripts/download-c2pa-libs.sh
	@echo "C2PA libraries setup complete."

# Build just the library for both device and simulator
library: download-libs
	@echo "Building C2PA library for device..."
	xcodebuild -project Library/Library.xcodeproj \
		-scheme "Library" \
		-configuration $(CONFIGURATION) \
		-destination "generic/platform=iOS" \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		build
	@echo "Building C2PA library for simulator..."
	xcodebuild -project Library/Library.xcodeproj \
		-scheme "Library" \
		-configuration $(CONFIGURATION) \
		-destination '$(SIMULATOR_DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		build
	@echo "Library build completed."

# Build TestShared framework
testshared:
	@echo "Building TestShared framework..."
	xcodebuild -workspace C2PA.xcworkspace \
		-scheme "TestShared" \
		-configuration $(DEBUG_CONFIGURATION) \
		-destination '$(SIMULATOR_DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		build
	@echo "TestShared build completed."

# Build SigningServer
signing-server:
	@echo "Building SigningServer..."
	xcodebuild -workspace C2PA.xcworkspace \
		-scheme "SigningServer" \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		build
	@echo "SigningServer build completed."

# Run tests
test: test-library run-tests

# Run library tests using the Library scheme
test-library: library testshared
	@echo "Running C2PA library tests with TestShared..."
	xcodebuild test \
		-workspace C2PA.xcworkspace \
		-scheme "Library" \
		-destination '$(SIMULATOR_DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA_PATH)
	@echo "C2PA library tests completed."

run-tests:
	@echo "Running TestApp tests..."
	xcodebuild test \
		-workspace C2PA.xcworkspace \
		-scheme "TestApp" \
		-destination '$(SIMULATOR_DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA_PATH)
	@echo "TestApp tests completed."

# Run ExampleApp in simulator
run-example:
	@echo "Building and running ExampleApp..."
	xcodebuild -workspace C2PA.xcworkspace \
		-scheme "ExampleApp" \
		-configuration $(DEBUG_CONFIGURATION) \
		-destination '$(SIMULATOR_DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		build

	@echo "Installing ExampleApp on simulator..."
	@xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || true
	@xcrun simctl install "iPhone 16 Pro" \
		"$(DERIVED_DATA_PATH)/Build/Products/$(DEBUG_CONFIGURATION)-iphonesimulator/ExampleApp.app"

	@echo "Launching ExampleApp..."
	@xcrun simctl launch "iPhone 16 Pro" org.contentauth.ExampleApp
	@echo "ExampleApp is running on the simulator."

# Run TestApp in simulator
run-testapp:
	@echo "Building and running TestApp..."
	xcodebuild -workspace C2PA.xcworkspace \
		-scheme "TestApp" \
		-configuration $(DEBUG_CONFIGURATION) \
		-destination '$(SIMULATOR_DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		build

	@echo "Installing TestApp on simulator..."
	@xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || true
	@xcrun simctl install "iPhone 16 Pro" \
		"$(DERIVED_DATA_PATH)/Build/Products/$(DEBUG_CONFIGURATION)-iphonesimulator/TestApp.app"

	@echo "Launching TestApp..."
	@xcrun simctl launch "iPhone 16 Pro" org.contentauth.TestApp
	@echo "TestApp is running on the simulator."

# Clean all build artifacts
clean:
	@echo "Cleaning all workspace build artifacts..."
	xcodebuild -workspace C2PA.xcworkspace \
		-scheme "C2PA" \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		clean
	@echo "Removing C2PA downloaded libraries..."
	@rm -rf Library/Build
	@rm -rf Library/Frameworks/C2PAC.xcframework
	@echo "Clean complete."

# Build library for distribution (with .swiftinterface files)
library-dist: download-libs
	@echo "Building C2PA library for distribution (device)..."
	xcodebuild -project Library/Library.xcodeproj \
		-scheme "Library" \
		-configuration $(CONFIGURATION) \
		-destination "generic/platform=iOS" \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
		SKIP_INSTALL=NO \
		build
	@echo "Building C2PA library for distribution (simulator)..."
	xcodebuild -project Library/Library.xcodeproj \
		-scheme "Library" \
		-configuration $(CONFIGURATION) \
		-destination "generic/platform=iOS Simulator" \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
		SKIP_INSTALL=NO \
		build
	@echo "Library distribution build completed."

# Create XCFramework for distribution
xcframework: library-dist
	@echo "Creating C2PA.xcframework for distribution..."
	@mkdir -p output
	@rm -rf output/C2PA.xcframework
	@xcodebuild -create-xcframework \
		-framework "$(DERIVED_DATA_PATH)/Build/Products/$(CONFIGURATION)-iphoneos/C2PA.framework" \
		-framework "$(DERIVED_DATA_PATH)/Build/Products/$(CONFIGURATION)-iphonesimulator/C2PA.framework" \
		-output output/C2PA.xcframework
	@echo "C2PA.xcframework created at output/C2PA.xcframework"

# Archive for distribution
archive:
	@echo "Creating archive..."
	xcodebuild archive \
		-workspace C2PA.xcworkspace \
		-scheme "C2PA" \
		-configuration $(CONFIGURATION) \
		-archivePath Build/C2PA.xcarchive
	@echo "Archive created at Build/C2PA.xcarchive"

# Export IPA from archive
export-ipa: archive
	@echo "Exporting IPA..."
	xcodebuild -exportArchive \
		-archivePath Build/C2PA.xcarchive \
		-exportPath Build/export \
		-exportOptionsPlist ExportOptions.plist
	@echo "IPA exported to Build/export/"

# Run code analysis
analyze:
	@echo "Running static analysis..."
	xcodebuild analyze \
		-workspace C2PA.xcworkspace \
		-scheme "C2PA" \
		-configuration $(DEBUG_CONFIGURATION)
	@echo "Analysis complete."

# Show available schemes
schemes:
	@echo "Available schemes:"
	@xcodebuild -workspace C2PA.xcworkspace -list | grep "Schemes:" -A 20

# Show build settings
settings:
	@echo "Build settings for C2PA scheme:"
	@xcodebuild -workspace C2PA.xcworkspace \
		-scheme "C2PA" \
		-showBuildSettings

# Quick build check - build TestApp only (fastest way to verify everything works)
quick: testapp
	@echo "Quick build check completed successfully!"

# Verify builds are working
verify: clean build
	@echo "Build verification completed successfully!"

# Help target
help:
	@echo "C2PA iOS - Xcode Build Commands"
	@echo "================================"
	@echo ""
	@echo "Build targets:"
	@echo "  make              - Build library, TestShared, and TestApp (default)"
	@echo "  make workspace    - Build all workspace projects"
	@echo "  make download-libs - Download C2PA libraries from GitHub"
	@echo "  make library      - Build C2PA library (downloads libs if needed)"
	@echo "  make testshared   - Build TestShared framework"
	@echo "  make testapp      - Build TestApp (includes dependencies)"
	@echo "  make signing-server - Build the SigningServer"
	@echo ""
	@echo "Testing:"
	@echo "  make test         - Run all tests (C2PA Library + TestApp)"
	@echo "  make test-library - Run C2PA library tests"
	@echo "  make run-tests    - Run TestApp tests"
	@echo ""
	@echo "Running apps:"
	@echo "  make run-example  - Build and run ExampleApp in simulator"
	@echo "  make run-testapp  - Build and run TestApp in simulator"
	@echo ""
	@echo "Distribution:"
	@echo "  make archive      - Create an archive for distribution"
	@echo "  make export-ipa   - Export IPA from archive"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean        - Clean all build artifacts"
	@echo "  make analyze      - Run static code analysis"
	@echo "  make schemes      - List available Xcode schemes"
	@echo "  make settings     - Show build settings"
	@echo "  make help         - Show this help message"
	@echo ""
	@echo "Quick targets:"
	@echo "  make quick        - Quick build check (TestApp only)"
	@echo "  make verify       - Clean and rebuild everything"
	@echo ""
	@echo "Configuration:"
	@echo "  CONFIGURATION=$(CONFIGURATION) (default)"
	@echo "  DEBUG_CONFIGURATION=$(DEBUG_CONFIGURATION)"
	@echo "  Architecture: $(ARCH) (Simulator: $(SIM_ARCH))"
	@echo "  DerivedData: $(DERIVED_DATA_PATH)"
	@echo ""
	@echo "Examples:"
	@echo "  make              - Build everything"
	@echo "  make quick        - Quick TestApp build to verify setup"
	@echo "  make clean build  - Clean rebuild"
	@echo "  make CONFIGURATION=Debug build - Debug build"
