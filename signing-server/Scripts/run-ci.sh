#!/bin/bash

# CI runner script for C2PA Signing Server

set -e

# Exit codes
SUCCESS=0
BUILD_FAILED=1
TEST_FAILED=2
STARTUP_FAILED=3

echo "C2PA Signing Server - CI Mode"
echo "=============================="

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo "Error: Package.swift not found. Please run this script from the server directory."
    exit $BUILD_FAILED
fi

# Create Resources directory
mkdir -p Resources

# Clean previous builds
echo "Cleaning previous builds..."
swift package clean

# Resolve dependencies
echo "Resolving dependencies..."
swift package resolve

# Build in release mode
echo "Building in release mode..."
if ! swift build -c release; then
    echo "Build failed!"
    exit $BUILD_FAILED
fi

# Run tests
echo "Running tests..."
if ! swift test; then
    echo "Tests failed!"
    exit $TEST_FAILED
fi

# Start server in background for integration tests
echo "Starting server for integration tests..."
.build/release/Run serve --env production --hostname 127.0.0.1 --port 8080 &
SERVER_PID=$!

# Wait for server to start
echo "Waiting for server to start..."
for i in {1..30}; do
    if curl -s http://localhost:8080/health > /dev/null; then
        echo "Server is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Server failed to start within 30 seconds"
        kill $SERVER_PID 2>/dev/null || true
        exit $STARTUP_FAILED
    fi
    sleep 1
done

# Run integration tests
echo "Running integration tests..."

# Test health endpoint
echo -n "Testing health endpoint... "
if curl -s http://localhost:8080/health | grep -q "200"; then
    echo "PASS"
else
    echo "FAIL"
    kill $SERVER_PID
    exit $TEST_FAILED
fi

# Test CA certificate endpoint
echo -n "Testing CA certificate endpoint... "
if curl -s http://localhost:8080/api/v1/certificates/ca | grep -q "rootCertificate"; then
    echo "PASS"
else
    echo "FAIL"
    kill $SERVER_PID
    exit $TEST_FAILED
fi

# Clean up
echo "Stopping server..."
kill $SERVER_PID

echo "CI tests completed successfully!"
exit $SUCCESS