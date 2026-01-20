# Overwhisper development commands

# Default: list available commands
default:
    @just --list

# Build the app in debug mode
build:
    swift build

# Build the app in release mode
build-release:
    swift build -c release

# Run the app (debug build)
run:
    swift run Overwhisper

# Run the app (release build)
run-release:
    swift run -c release Overwhisper

# Clean build artifacts
clean:
    swift package clean
    rm -rf .build

# Update dependencies
update:
    swift package update

# Resolve dependencies
resolve:
    swift package resolve

# Open in Xcode
xcode:
    open Package.swift

# Show dependency tree
deps:
    swift package show-dependencies

# Build and create app bundle
bundle: build-release
    #!/usr/bin/env bash
    set -euo pipefail
    APP_NAME="Overwhisper"
    BUNDLE_DIR="${APP_NAME}.app"
    CONTENTS_DIR="${BUNDLE_DIR}/Contents"
    MACOS_DIR="${CONTENTS_DIR}/MacOS"
    RESOURCES_DIR="${CONTENTS_DIR}/Resources"

    rm -rf "${BUNDLE_DIR}"
    mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

    cp .build/release/Overwhisper "${MACOS_DIR}/"
    cp Overwhisper/Info.plist "${CONTENTS_DIR}/"

    if [ -d "Overwhisper/Resources" ]; then
        cp -r Overwhisper/Resources/* "${RESOURCES_DIR}/" 2>/dev/null || true
    fi

    echo "Created ${BUNDLE_DIR}"
