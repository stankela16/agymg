#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT_DIR/version.env" ]]; then
  source "$ROOT_DIR/version.env"
fi
APP_NAME=${APP_NAME:-agymg}
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"

echo "==> Stopping any running ${APP_NAME}..."
pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
pkill -x "${APP_NAME}" 2>/dev/null || true

echo "==> Packaging application..."
"${ROOT_DIR}/Scripts/package_app.sh" release

echo "==> Installing to /Applications..."
rm -rf "/Applications/${APP_NAME}.app"
ditto "${APP_BUNDLE}" "/Applications/${APP_NAME}.app"
xattr -cr "/Applications/${APP_NAME}.app"
rm -rf "${APP_BUNDLE}" "${ROOT_DIR}/${APP_NAME}.zip"

echo "==> Launching ${APP_NAME}..."
open "/Applications/${APP_NAME}.app"

for _ in {1..10}; do
  if pgrep -f "${APP_NAME}" >/dev/null 2>&1; then
    echo "==> AntigravityManager is running."
    exit 0
  fi
  sleep 0.3
done

echo "==> App launched."
