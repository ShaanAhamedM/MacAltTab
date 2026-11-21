#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

APP_NAME="MacAltTab"
APP_BUNDLE="${PROJECT_ROOT}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> [1/4] Building ${APP_NAME} (Release arm64)..."
swift build -c release

echo "==> [2/4] Running offline security & 100-iteration memory leak self-test..."
"./.build/release/${APP_NAME}" --self-test

echo "==> [3/4] Packaging ${APP_NAME}.app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "./.build/release/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
cp "${PROJECT_ROOT}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

echo "==> [4/4] Signing ${APP_NAME}.app with hardened offline entitlements..."
SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}' || true)
SIGNED_OK=false
if [[ -n "${SIGNING_IDENTITY}" ]]; then
    echo "    Trying keychain identity: ${SIGNING_IDENTITY}"
    if codesign --force --deep --options runtime --sign "${SIGNING_IDENTITY}" --entitlements "${PROJECT_ROOT}/Resources/MacAltTab.entitlements" "${APP_BUNDLE}" 2>/dev/null; then
        SIGNED_OK=true
    else
        echo "    Keychain identity unavailable in non-interactive shell; falling back to ad-hoc signing (-)"
    fi
fi

if [[ "${SIGNED_OK}" != "true" ]]; then
    codesign --force --deep --sign - --entitlements "${PROJECT_ROOT}/Resources/MacAltTab.entitlements" "${APP_BUNDLE}"
fi

echo "==> Verifying code signature..."
codesign --verify --verbose=2 "${APP_BUNDLE}"
codesign -dvvv "${APP_BUNDLE}" 2>&1 | grep -E "Authority=|Identifier=|TeamIdentifier=|Signature=|CDHash=" || true

echo "==> Build complete: ${APP_BUNDLE}"
