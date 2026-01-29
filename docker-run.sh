#!/bin/bash
#
# docker-run.sh - Convenience script for running the T440s BIOS fix container
#
# Usage:
#   ./docker-run.sh                     # Interactive shell
#   ./docker-run.sh prepare_bios.sh ... # Run the BIOS preparation script
#
# Environment variables:
#   BIOS_FIX_IMAGE - Override the Docker image to use (e.g., ghcr.io/owner/repo:latest)
#

LOCAL_IMAGE="t440s-bios-fix"
IMAGE_NAME="${BIOS_FIX_IMAGE:-$LOCAL_IMAGE}"

# If using local image, check if it exists and build if not
if [ "$IMAGE_NAME" = "$LOCAL_IMAGE" ]; then
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        echo "Docker image '$IMAGE_NAME' not found. Building..."
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        docker build -t "$IMAGE_NAME" "$SCRIPT_DIR" || exit 1
        echo "Image built successfully."
        echo ""
    fi
else
    # Using remote image - pull latest if not present
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        echo "Pulling image '$IMAGE_NAME'..."
        docker pull "$IMAGE_NAME" || exit 1
        echo ""
    fi
fi

# Determine Docker run options based on OS
DOCKER_OPTS="--rm -it -v $(pwd):/work"

# On Linux, add USB device access for flashrom
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Check if /dev/bus/usb exists
    if [ -d "/dev/bus/usb" ]; then
        DOCKER_OPTS="$DOCKER_OPTS --device=/dev/bus/usb"
        echo "Note: USB device access enabled (Linux)"
    fi
else
    echo "Note: Running on $OSTYPE - USB device access not available in Docker."
    echo "      Use native flashrom for the actual flashing step."
fi

# Run the container
if [ $# -eq 0 ]; then
    # No arguments - start interactive shell
    docker run $DOCKER_OPTS "$IMAGE_NAME"
else
    # Arguments provided - run as command
    docker run $DOCKER_OPTS "$IMAGE_NAME" -c "$*"
fi
