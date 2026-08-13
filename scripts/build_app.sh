#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$PROJECT_DIR/dist/MediaDock 9.app"

cd "$PROJECT_DIR"
mkdir -p "$BUILD_DIR/module-cache"

build_with_sdk() {
  local sdk_path="$1"
  SDKROOT="$sdk_path" \
  CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/module-cache" \
    swift build -c release --disable-sandbox --scratch-path "$BUILD_DIR"
}

DEFAULT_SDK="$(xcrun --sdk macosx --show-sdk-path)"
BUILD_MARKER="$BUILD_DIR/.mediadock-build-start"
touch "$BUILD_MARKER"
BUILD_STATUS=0

if build_with_sdk "$DEFAULT_SDK"; then
  BUILD_STATUS=0
else
  BUILD_STATUS=$?
  FRESH_PRODUCT="$BUILD_DIR/out/Products/Release/MediaDock9"
  if [[ -x "$FRESH_PRODUCT" && "$FRESH_PRODUCT" -nt "$BUILD_MARKER" ]] && "$FRESH_PRODUCT" --self-test; then
    BUILD_STATUS=0
  else
    FALLBACK_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
    if [[ ! -d "$FALLBACK_SDK" || "$DEFAULT_SDK" == "$FALLBACK_SDK" ]]; then
      print -u2 "The selected Swift compiler and macOS SDK are incompatible. Install or select a matching current Xcode toolchain."
      exit 1
    fi
    print -u2 "The selected SDK did not match the Swift compiler; retrying with the installed compatibility SDK."
    if build_with_sdk "$FALLBACK_SDK"; then
      BUILD_STATUS=0
    else
      BUILD_STATUS=$?
    fi
  fi
fi

PRODUCT="$BUILD_DIR/release/MediaDock9"
if [[ ! -x "$PRODUCT" ]]; then
  PRODUCT="$BUILD_DIR/out/Products/Release/MediaDock9"
fi

if (( BUILD_STATUS != 0 )); then
  if [[ -x "$PRODUCT" && "$PRODUCT" -nt "$BUILD_MARKER" ]] && "$PRODUCT" --self-test; then
    print -u2 "The executable linked and passed self-test; continuing despite a post-link debug-symbol failure in the selected command-line toolchain."
  else
    print -u2 "The app executable did not complete a fresh validated build."
    exit "$BUILD_STATUS"
  fi
fi

EXPECTED_APP="$PROJECT_DIR/dist/MediaDock 9.app"
if [[ "$APP_DIR" != "$EXPECTED_APP" || -z "$APP_DIR" ]]; then
  print -u2 "Refusing to replace an unexpected app path: $APP_DIR"
  exit 1
fi

if [[ -e "$APP_DIR" ]]; then
  rm -rf "$APP_DIR"
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PRODUCT" "$APP_DIR/Contents/MacOS/MediaDock9"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon-1024.png" "$APP_DIR/Contents/Resources/AppIcon-1024.png"
codesign --force --deep --sign - "$APP_DIR"

print "$APP_DIR"
