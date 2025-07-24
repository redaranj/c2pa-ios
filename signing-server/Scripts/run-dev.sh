#!/bin/bash

# Development runner script for C2PA Signing Server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}C2PA Signing Server - Development Mode${NC}"
echo "======================================"

# Check if we're in the right directory
if [ ! -f "Package.swift" ]; then
    echo -e "${RED}Error: Package.swift not found. Please run this script from the server directory.${NC}"
    exit 1
fi

# Create Resources directory if it doesn't exist
if [ ! -d "Resources" ]; then
    echo -e "${YELLOW}Creating Resources directory...${NC}"
    mkdir -p Resources
fi

# Check for Swift
if ! command -v swift &> /dev/null; then
    echo -e "${RED}Error: Swift is not installed or not in PATH${NC}"
    exit 1
fi

# Clean and resolve packages
echo -e "${YELLOW}Resolving package dependencies...${NC}"
swift package resolve

# Build the project
echo -e "${YELLOW}Building project...${NC}"
swift build

# Run the server
echo -e "${GREEN}Starting server on http://localhost:8080${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

# Set environment variables for development
export VAPOR_ENVIRONMENT=development
export LOG_LEVEL=debug

# Run with environment variables
swift run Run serve --env development --hostname 127.0.0.1 --port 8080