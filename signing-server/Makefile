# Makefile for C2PA Signing Server

.PHONY: setup run test clean build release

# Setup development environment
setup:
	@echo "Setting up development environment..."
	@mkdir -p Resources
	@echo "Resolving Swift package dependencies..."
	@swift package resolve
	@echo "Setup complete!"

# Run in development mode
run: setup
	@echo "Starting server in development mode..."
	@swift run Run serve --env development --hostname 127.0.0.1 --port 8080

# Run in production mode
run-production: setup
	@echo "Building release version..."
	@swift build -c release
	@echo "Starting server in production mode..."
	@.build/release/Run serve --env production --hostname 0.0.0.0 --port 8080

# Build release binary
build:
	@echo "Building release binary..."
	@swift build -c release

# Run tests
test:
	@echo "Running tests..."
	@swift test

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@swift package clean
	@rm -rf .build


# Development with file watching (requires swift-dev)
watch:
	@echo "Starting with file watching..."
	@if command -v swift-dev >/dev/null 2>&1; then \
		swift-dev; \
	else \
		echo "swift-dev not found. Install it with: brew install swift-dev"; \
		exit 1; \
	fi

# Generate Xcode project
xcode:
	@echo "Generating Xcode project..."
	@swift package generate-xcodeproj
	@open *.xcodeproj

# Check for required dependencies
check-deps:
	@echo "Checking dependencies..."
	@command -v swift >/dev/null 2>&1 || { echo "Swift is required but not installed."; exit 1; }
	@command -v openssl >/dev/null 2>&1 || { echo "OpenSSL is required but not installed."; exit 1; }
	@echo "All dependencies are installed!"

# Help
help:
	@echo "Available commands:"
	@echo "  make setup          - Set up development environment"
	@echo "  make run            - Run server in development mode"
	@echo "  make run-production - Run server in production mode"
	@echo "  make build          - Build release binary"
	@echo "  make test           - Run tests"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make watch          - Run with file watching (requires swift-dev)"
	@echo "  make xcode          - Generate and open Xcode project"
	@echo "  make check-deps     - Check for required dependencies"
	@echo "  make help           - Show this help message"