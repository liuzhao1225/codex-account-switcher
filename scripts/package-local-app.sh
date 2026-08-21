#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$BUILD_DIR/Codex Account Switcher Lite.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$PROJECT_DIR"
swift build -c release

mkdir -p "$MACOS_DIR"
cp "$BUILD_DIR/CodexAccountSwitcherLite" "$MACOS_DIR/CodexAccountSwitcherLite"
chmod 0755 "$MACOS_DIR/CodexAccountSwitcherLite"

/usr/bin/plutil -create xml1 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleDevelopmentRegion -string en "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string "Codex Account Switcher Lite" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string CodexAccountSwitcherLite "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string com.liuzhao.codex-account-switcher-lite "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleName -string "Codex Account Switcher Lite" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string 0.1.0 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string 1 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 14.0 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert LSUIElement -bool true "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$CONTENTS_DIR/Info.plist"

echo "$APP_DIR"
