.PHONY: all clean library test-shared test-app example-app publish tests coverage help \
        run-test-app run-example-app signing-server-start signing-server-stop signing-server-status \
        tests-with-server workspace-build test-library

# Build configuration
CONFIGURATION := Release
SDK := iphoneos
# Default destination - can be overridden from command line
DESTINATION ?= platform=iOS Simulator,name=iPhone 16 Pro

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
	@xcodebuild test -workspace C2PA.xcworkspace -scheme Library -configuration Debug -enableCodeCoverage YES -destination '$(DESTINATION)'
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

# Archive library for distribution
publish: library
	@echo "Archiving library..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme Library -configuration Release archive
	@echo "Library archived. Ready for distribution."

# Tests with signing server
tests-with-server: signing-server-start tests signing-server-stop
	@echo "Tests with server completed."

# Start the signing server (setup is handled by Xcode scheme)
signing-server-start:
	@echo "Building and starting signing server..."
	@xcodebuild -workspace C2PA.xcworkspace -scheme SigningServer -configuration Debug build
	@cd SigningServer && swift run SigningServer > ../signing-server.log 2>&1 &
	@echo "Signing server started. Check signing-server.log for details."
	@echo "Server running at http://localhost:8080"

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
	@xcodebuild -workspace C2PA.xcworkspace -scheme SigningServer clean
	@rm -rf SigningServer/.build
	@rm -rf build
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
	@echo "  make publish      - Prepare library for publishing"
	@echo "  make signing-server-start - Start the signing server"
	@echo "  make signing-server-stop  - Stop the signing server"
	@echo "  make signing-server-status - Check server status"
	@echo "  make tests-with-server - Run tests with signing server"
	@echo "  make clean        - Clean all build artifacts"
	@echo "  make help         - Show this help message"
