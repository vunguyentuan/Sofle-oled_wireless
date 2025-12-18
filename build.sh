#!/bin/bash
set -e

# ZMK Firmware Build Script for Sofle Keyboard
# Uses Docker for consistent builds without local toolchain setup

BOARD="nice_nano_v2"
SHIELDS=("sofle_left" "sofle_right" "settings_reset")
ZMK_IMAGE="zmkfirmware/zmk-build-arm:stable"
OUTPUT_DIR="firmware"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

print_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Check for Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first:"
    echo "  brew install --cask docker"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    print_error "Docker is not running. Please start Docker Desktop."
    exit 1
fi

# Parse arguments
BUILD_ALL=true
SELECTED_SHIELD=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--left)
            BUILD_ALL=false
            SELECTED_SHIELD="sofle_left"
            shift
            ;;
        -r|--right)
            BUILD_ALL=false
            SELECTED_SHIELD="sofle_right"
            shift
            ;;
        -s|--settings-reset)
            BUILD_ALL=false
            SELECTED_SHIELD="settings_reset"
            shift
            ;;
        -h|--help)
            echo "ZMK Firmware Build Script for Sofle Keyboard"
            echo ""
            echo "Usage: ./build.sh [options]"
            echo ""
            echo "Options:"
            echo "  -l, --left            Build only left half"
            echo "  -r, --right           Build only right half"
            echo "  -s, --settings-reset  Build only settings reset firmware"
            echo "  -h, --help            Show this help message"
            echo ""
            echo "Without options, builds all firmware variants."
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Pull the ZMK build image
print_status "Pulling ZMK build image..."
docker pull "$ZMK_IMAGE"

# Create a temporary directory for the build
BUILD_CONTAINER="zmk-build-$$"
WORKSPACE="/workspace"

print_status "Setting up build environment..."

# Initialize west workspace and build
build_firmware() {
    local shield=$1
    print_status "Building firmware for: $shield"

    docker run --rm \
        -v "$(pwd)/config:${WORKSPACE}/config:ro" \
        -v "$(pwd)/${OUTPUT_DIR}:${WORKSPACE}/output" \
        -w "$WORKSPACE" \
        "$ZMK_IMAGE" \
        bash -c "
            set -e

            # Initialize west workspace
            west init -l config 2>/dev/null || true
            west update --narrow -o=--depth=1

            # Build the firmware
            west build -s zmk/app -p -b ${BOARD} -- \
                -DSHIELD=${shield} \
                -DZMK_CONFIG=${WORKSPACE}/config

            # Copy output
            cp build/zephyr/zmk.uf2 output/${shield}-${BOARD}.uf2

            echo 'Build complete!'
        "

    if [[ -f "${OUTPUT_DIR}/${shield}-${BOARD}.uf2" ]]; then
        print_status "Successfully built: ${OUTPUT_DIR}/${shield}-${BOARD}.uf2"
    else
        print_error "Build failed for $shield"
        return 1
    fi
}

# Build selected or all shields
if [[ "$BUILD_ALL" == true ]]; then
    for shield in "${SHIELDS[@]}"; do
        build_firmware "$shield"
        echo ""
    done
else
    build_firmware "$SELECTED_SHIELD"
fi

print_status "Build complete! Firmware files are in the '${OUTPUT_DIR}' directory:"
ls -la "$OUTPUT_DIR"/*.uf2 2>/dev/null || print_warning "No firmware files found"

echo ""
echo "To flash:"
echo "  1. Double-tap reset on your Nice Nano to enter bootloader"
echo "  2. Copy the .uf2 file to the mounted drive"
echo "     - sofle_left-nice_nano_v2.uf2  -> Left half"
echo "     - sofle_right-nice_nano_v2.uf2 -> Right half"
