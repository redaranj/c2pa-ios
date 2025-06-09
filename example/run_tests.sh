#!/bin/bash

# Build the test target
echo "Building test target..."
xcodebuild build-for-testing \
    -project C2PAExample.xcodeproj \
    -scheme C2PAExample \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -derivedDataPath build

# Run the tests
echo "Running tests..."
xcodebuild test-without-building \
    -project C2PAExample.xcodeproj \
    -scheme C2PAExample \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -derivedDataPath build \
    -test-language en \
    -test-region US \
    -only-testing:C2PAExampleTests