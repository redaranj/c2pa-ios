.PHONY: all clean build test run-tests run-example run-testapp help \
        workspace library signing-server

# Configuration
CONFIGURATION := Release
DEBUG_CONFIGURATION := Debug
SIMULATOR_DESTINATION := platform=iOS Simulator,name=iPhone 15
# DerivedData follows Apple's convention - in Build directory under workspace root
DERIVED_DATA_PATH := Build/DerivedData

# Default target
all: build

# Build the entire workspace
build: workspace

# Build the workspace with all targets
workspace:
	@echo "Building C2PA workspace..."
	xcodebuild -workspace C2PA.xcworkspace \
		-scheme "C2PA" \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		build
	@echo "Workspace build completed."

# Build just the library
library:
	@echo "Building C2PA library..."
	xcodebuild -project Library/Library.xcodeproj \
		-scheme "C2PA" \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		build
	@echo "Library build completed."

# Build SigningServer
signing-server:
	@echo "Building SigningServer..."
	xcodebuild -project SigningServer/SigningServer.xcodeproj \
		-scheme "SigningServer" \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		build
	@echo "SigningServer build completed."

# Run tests
test: run-tests

run-tests:
	@echo "Running tests..."
	xcodebuild test \
		-workspace C2PA.xcworkspace \
		-scheme "TestApp" \
		-destination '$(SIMULATOR_DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA_PATH)
	@echo "Tests completed."

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
	@xcrun simctl boot "iPhone 15" 2>/dev/null || true
	@xcrun simctl install "iPhone 15" \
		"$(DERIVED_DATA_PATH)/Build/Products/$(DEBUG_CONFIGURATION)-iphonesimulator/ExampleApp.app"

	@echo "Launching ExampleApp..."
	@xcrun simctl launch "iPhone 15" org.contentauth.ExampleApp
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
	@xcrun simctl boot "iPhone 15" 2>/dev/null || true
	@xcrun simctl install "iPhone 15" \
		"$(DERIVED_DATA_PATH)/Build/Products/$(DEBUG_CONFIGURATION)-iphonesimulator/TestApp.app"

	@echo "Launching TestApp..."
	@xcrun simctl launch "iPhone 15" org.contentauth.TestApp
	@echo "TestApp is running on the simulator."

# Clean all build artifacts
clean:
	@echo "Cleaning build artifacts..."
	xcodebuild -workspace C2PA.xcworkspace \
		-scheme "C2PA" \
		-derivedDataPath $(DERIVED_DATA_PATH) \
		clean
	@echo "Clean complete."

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

# Help target
help:
	@echo "C2PA iOS - Xcode Build Commands"
	@echo "================================"
	@echo ""
	@echo "Build targets:"
	@echo "  make              - Build the entire workspace (default)"
	@echo "  make workspace    - Build all workspace projects"
	@echo "  make library      - Build just the C2PA library"
	@echo "  make signing-server - Build the SigningServer"
	@echo ""
	@echo "Testing:"
	@echo "  make test         - Run all tests"
	@echo "  make run-tests    - Run tests (alias for 'test')"
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
	@echo "Configuration:"
	@echo "  CONFIGURATION=$(CONFIGURATION) (default)"
	@echo "  Use 'make CONFIGURATION=Debug build' for debug builds"
