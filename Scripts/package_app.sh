#!/usr/bin/env bash
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [[ -f "$ROOT/version.env" ]]; then
  source "$ROOT/version.env"
fi

APP_NAME=${APP_NAME:-agymg}
BUNDLE_ID=${BUNDLE_ID:-com.nikolastanojevic.agymg}
MACOS_MIN_VERSION=${MACOS_MIN_VERSION:-14.0}
MENU_BAR_APP=${MENU_BAR_APP:-0}
SIGNING_MODE=${SIGNING_MODE:-adhoc}
APP_IDENTITY=${APP_IDENTITY:-}
MARKETING_VERSION=${MARKETING_VERSION:-1.0.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}

HOST_ARCH=$(uname -m)
ARCH_LIST=("$HOST_ARCH")

echo "==> Building ${APP_NAME} (${CONF}) for ${HOST_ARCH}..."
if [[ "$CONF" == "release" ]]; then
  swift build --disable-sandbox -c "$CONF" --arch "$HOST_ARCH" -Xswiftc -strict-concurrency=complete
else
  swift build --disable-sandbox -c "$CONF" --arch "$HOST_ARCH"
fi

APP="$ROOT/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

LSUI_VALUE="false"
if [[ "$MENU_BAR_APP" == "1" ]]; then
  LSUI_VALUE="true"
fi

BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "initial")

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
    <key>LSUIElement</key><${LSUI_VALUE}/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
    <key>NSDesktopFolderUsageDescription</key><string>agymg needs access to your selected projects directory to discover workspaces and synchronize MCP servers, skills, and plugins.</string>
</dict>
</plist>
PLIST

BIN_PATH=".build/${HOST_ARCH}-apple-macosx/$CONF/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  BIN_PATH=".build/$CONF/$APP_NAME"
fi

cp "$BIN_PATH" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

# Copy resources if exist
RESOURCE_DIR="$ROOT/Sources/$APP_NAME/Resources"
if [[ ! -d "$RESOURCE_DIR" ]]; then
  RESOURCE_DIR="$ROOT/Sources/AntigravityManager/Resources"
fi
if [[ -d "$RESOURCE_DIR" ]]; then
  cp -R "$RESOURCE_DIR/." "$APP/Contents/Resources/"
fi

# SwiftPM resource bundles (direct glob loop safe under bash 3.2 set -u)
for bundle in ".build/${HOST_ARCH}-apple-macosx/$CONF/"*.bundle ".build/$CONF/"*.bundle; do
  if [[ -d "$bundle" ]]; then
    bundle_name=$(basename "$bundle")
    rm -rf "$APP/Contents/Resources/$bundle_name"
    cp -R "$bundle" "$APP/Contents/Resources/"
  fi
done

chmod -R u+w "$APP"
find "$APP" -name ".DS_Store" -delete 2>/dev/null || true
find "$APP" -name "._*" -delete 2>/dev/null || true
xattr -cr "$APP" 2>/dev/null || true

# If $APP is in a FileProvider/iCloud synced location (such as Desktop/Projects),
# macOS fileproviderd can re-inject com.apple.FinderInfo. We stage and sign in a clean
# temporary directory, then ditto back preserving the valid signature.
STAGE_DIR=$(mktemp -d -t app_sign_stage)
trap 'rm -rf "$STAGE_DIR"' EXIT
ditto "$APP" "$STAGE_DIR/${APP_NAME}.app"
STAGE_APP="$STAGE_DIR/${APP_NAME}.app"
find "$STAGE_APP" -name ".DS_Store" -delete 2>/dev/null || true
find "$STAGE_APP" -name "._*" -delete 2>/dev/null || true
xattr -cr "$STAGE_APP" 2>/dev/null || true

if [[ "$SIGNING_MODE" == "identity" && -n "$APP_IDENTITY" ]]; then
  codesign --force --deep --sign "$APP_IDENTITY" "$STAGE_APP"
else
  codesign --force --deep -r "=designated => identifier \"${BUNDLE_ID}\"" -s - "$STAGE_APP"
fi

echo "==> Verifying code signature..."
codesign --verify --deep --strict "$STAGE_APP"

rm -f "$ROOT/${APP_NAME}.zip"
ditto -c -k --sequesterRsrc --keepParent "$STAGE_APP" "$ROOT/${APP_NAME}.zip"

rm -rf "$APP"
ditto "$STAGE_APP" "$APP"
xattr -cr "$APP" 2>/dev/null || true
codesign --verify --deep --strict "$APP" 2>/dev/null || codesign --verify --deep "$APP"

echo "==> Code signature verified (strict): ${APP}"
echo "==> Successfully packaged ${APP} and ${ROOT}/${APP_NAME}.zip"
