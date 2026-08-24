#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
RESOURCE_BUNDLE="CodexAccountSwitcherLite_CodexAccountSwitcherLite.bundle"
APP_VERSION=${RELEASE_VERSION:-0.1.1}

cd "$PROJECT_DIR"
BUILD_ARGUMENTS=(-c release)
if [[ -n "${SWIFT_BUILD_ARCH:-}" ]]; then
    BUILD_ARGUMENTS+=(--arch "$SWIFT_BUILD_ARCH")
fi

swift build "${BUILD_ARGUMENTS[@]}"
BUILD_DIR=$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)
APP_DIR="$BUILD_DIR/Codex Account Switcher Lite.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/CodexAccountSwitcherLite" "$MACOS_DIR/CodexAccountSwitcherLite"
chmod 0755 "$MACOS_DIR/CodexAccountSwitcherLite"
ditto "$BUILD_DIR/$RESOURCE_BUNDLE" "$RESOURCES_DIR/$RESOURCE_BUNDLE"

/usr/bin/plutil -create xml1 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleDevelopmentRegion -string en "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string "Codex Account Switcher Lite" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string CodexAccountSwitcherLite "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string com.liuzhao.codex-account-switcher-lite "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleName -string "Codex Account Switcher Lite" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string 1 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 14.0 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert LSUIElement -bool true "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
