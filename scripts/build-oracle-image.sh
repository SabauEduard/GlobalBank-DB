#!/usr/bin/env bash
# Build oracle/database:19.3.0-ee Docker image from the downloaded zip.
# Run once before `docker compose up`.
#
# Prerequisites:
#   - Docker Desktop running
#   - LINUX.ARM64_1919000_db_home.zip in the project root
#
# Usage: bash scripts/build-oracle-image.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ZIP_SRC="$ROOT/LINUX.ARM64_1919000_db_home.zip"
BUILD_DIR="$HOME/oracle-docker-images"
DOCKERFILE_DIR="$BUILD_DIR/OracleDatabase/SingleInstance/dockerfiles"
VERSION="19.3.0"
IMAGE="oracle/database:${VERSION}-ee"

echo "=== GlobalBank — Oracle 19c Docker Image Builder ==="

# 1. Check zip exists
if [ ! -f "$ZIP_SRC" ]; then
  echo "ERROR: $ZIP_SRC not found."
  echo "Download LINUX.ARM64_1919000_db_home.zip and place it in the project root."
  exit 1
fi

# 2. Check if image already built
if docker image inspect "$IMAGE" &>/dev/null; then
  echo "Image $IMAGE already exists — skipping build."
  exit 0
fi

# 3. Clone oracle/docker-images if needed
if [ ! -d "$BUILD_DIR" ]; then
  echo "Cloning oracle/docker-images..."
  git clone https://github.com/oracle/docker-images "$BUILD_DIR"
else
  echo "oracle/docker-images already cloned at $BUILD_DIR"
fi

# 4. Copy zip into the right place
DEST="$DOCKERFILE_DIR/$VERSION/LINUX.ARM64_1919000_db_home.zip"
if [ ! -f "$DEST" ]; then
  echo "Copying zip to $DEST ..."
  cp "$ZIP_SRC" "$DEST"
else
  echo "Zip already in place."
fi

# 5. Build image (~15-20 min on first run)
echo ""
echo "Building $IMAGE — this takes 15-20 minutes..."
cd "$DOCKERFILE_DIR"
./buildContainerImage.sh -v "$VERSION" -e

echo ""
echo "=== Build complete: $IMAGE ==="
echo "Next: docker compose -f docker/docker-compose.yml up -d"
