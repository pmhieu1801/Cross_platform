#!/bin/bash
# run_macos.sh - Flutter macOS launcher (workaround for iCloud Drive xattr issue)
# Usage: ./run_macos.sh

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$PROJECT_DIR/build/macos/Build/Products/Debug/ex1.app"

echo "🔨 Building Flutter macOS app..."
flutter build macos --debug 2>&1 || true

if [ ! -d "$APP_PATH" ]; then
  echo "❌ Build failed - no .app found"
  exit 1
fi

echo "🧹 Clearing extended attributes (iCloud xattr fix)..."
xattr -cr "$APP_PATH"

echo "✍️  Re-signing with ad-hoc identity..."
codesign --force --deep --sign - "$APP_PATH"

echo "🚀 Launching app..."
open "$APP_PATH"
echo "✅ Done!"
