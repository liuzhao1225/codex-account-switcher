#!/bin/zsh

set -euo pipefail

: "${RELEASE_VERSION:?Set RELEASE_VERSION, for example 0.1.0}"
: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the Developer ID Application certificate name}"
: "${APPLE_API_KEY:?Set APPLE_API_KEY to the App Store Connect .p8 path}"
: "${APPLE_API_KEY_ID:?Set APPLE_API_KEY_ID}"
: "${APPLE_API_ISSUER:?Set APPLE_API_ISSUER}"

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
ARTIFACT_DIR="$PROJECT_DIR/.build/artifacts"
ZIP_PATH="$ARTIFACT_DIR/Codex-Account-Switcher-Lite-v${RELEASE_VERSION}-macos-arm64.zip"
NOTARY_RESULT="$ARTIFACT_DIR/notary-result.json"

cd "$PROJECT_DIR"
APP_PATH=$("$SCRIPT_DIR/package-local-app.sh" | tail -n 1)
APP_VERSION=$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")
if [[ "$APP_VERSION" != "$RELEASE_VERSION" ]]; then
    echo "Release version $RELEASE_VERSION does not match app version $APP_VERSION." >&2
    exit 1
fi

codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" \
    "$APP_PATH"
codesign --verify --deep --strict --verbose=4 "$APP_PATH"

mkdir -p "$ARTIFACT_DIR"
rm -f "$ZIP_PATH" "$NOTARY_RESULT"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
    --key "$APPLE_API_KEY" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER" \
    --wait \
    --output-format json | tee "$NOTARY_RESULT"

NOTARY_STATUS=$(/usr/bin/plutil -extract status raw "$NOTARY_RESULT")
if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    echo "Apple notarization finished with status: $NOTARY_STATUS" >&2
    exit 1
fi

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
codesign --verify --deep --strict --verbose=4 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH"
echo "$ZIP_PATH"
