#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD_DIR="${BUILD_DIR:-$(mktemp -d /private/tmp/codexquota.XXXXXX)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_GROUP="${APP_GROUP:-group.local.codexquota}"
mkdir -p "$BUILD_DIR/Codex 周额度.app/Contents/MacOS" "$BUILD_DIR/Codex 周额度.app/Contents/PlugIns/CodexQuotaWidget.appex/Contents/MacOS" "$BUILD_DIR/module-cache"
APP="$BUILD_DIR/Codex 周额度.app"
EXT="$APP/Contents/PlugIns/CodexQuotaWidget.appex"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
mkdir -p "$APP/Contents/Resources" "$EXT/Contents/Resources"
cp Assets/AppIcon-rounded.icns "$APP/Contents/Resources/QuotaAppIcon-v6.icns"
cp Assets/AppIcon-rounded.icns "$EXT/Contents/Resources/QuotaAppIcon-v6.icns"
python3 scripts/metadata.py "$APP" "$EXT" "$APP_GROUP" "$BUILD_DIR"
for arch in arm64 x86_64; do
    mkdir -p "$BUILD_DIR/$arch"
    xcrun swiftc -swift-version 5 -parse-as-library -O -target "$arch-apple-macos26.0" Sources/Quota.swift Sources/CodexClient.swift Sources/CodexLocation.swift Sources/LocalQuotaServer.swift Sources/QuotaView.swift Sources/QuotaApp.swift -o "$BUILD_DIR/$arch/CodexQuota"
    xcrun swiftc -swift-version 5 -parse-as-library -application-extension -Xlinker -e -Xlinker _NSExtensionMain -O -target "$arch-apple-macos26.0" Sources/Quota.swift Sources/QuotaView.swift Sources/QuotaWidget.swift -o "$BUILD_DIR/$arch/CodexQuotaWidget"
done
xcrun lipo -create "$BUILD_DIR/arm64/CodexQuota" "$BUILD_DIR/x86_64/CodexQuota" -output "$APP/Contents/MacOS/CodexQuota"
xcrun lipo -create "$BUILD_DIR/arm64/CodexQuotaWidget" "$BUILD_DIR/x86_64/CodexQuotaWidget" -output "$EXT/Contents/MacOS/CodexQuotaWidget"
sign_options=(--options runtime)
if [[ "$SIGN_IDENTITY" != "-" ]]; then sign_options+=(--timestamp); fi
codesign --force --sign "$SIGN_IDENTITY" "${sign_options[@]}" --entitlements "$BUILD_DIR/widget.entitlements" "$EXT"
codesign --force --sign "$SIGN_IDENTITY" "${sign_options[@]}" --entitlements "$BUILD_DIR/app.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$APP"
