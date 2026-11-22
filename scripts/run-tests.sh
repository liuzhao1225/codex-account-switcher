#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
cd "$PROJECT_DIR"

DEV_DIR=$(xcode-select -p 2>/dev/null || true)
if [[ "$DEV_DIR" != "/Library/Developer/CommandLineTools" ]] && xcrun --find xctest >/dev/null 2>&1; then
    exec swift test "$@"
fi

# Command Line Tools fallback: build the Swift Testing bundle with the native llbuild backend
# and invoke Testing.__swiftPMEntryPoint() directly.
swift test --build-system native --enable-swift-testing --disable-xctest "$@"
BIN_DIR=$(swift build --build-system native --show-bin-path)
BUNDLE="$BIN_DIR/CodexAccountSwitcherPackageTests.xctest/Contents/MacOS/CodexAccountSwitcherPackageTests"
SWIFT_BIN=$(xcrun --find swift)
TOOLCHAIN_ROOT=${SWIFT_BIN:h:h:h}
FRAMEWORKS_DIR="$TOOLCHAIN_ROOT/Library/Developer/Frameworks"
LIBS_DIR="$TOOLCHAIN_ROOT/Library/Developer/usr/lib"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/switcher-test-runner.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/Runner.swift" <<EOF
import Darwin
import Testing
@main struct LocalRunner {
    static func main() async {
        guard dlopen("$BUNDLE", RTLD_NOW | RTLD_GLOBAL) != nil else {
            fatalError(String(cString: dlerror()))
        }
        await Testing.__swiftPMEntryPoint() as Never
    }
}
EOF

swiftc -parse-as-library "$TMP_DIR/Runner.swift" \
    -F "$FRAMEWORKS_DIR" -framework Testing \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS_DIR" \
    -Xlinker -rpath -Xlinker "$LIBS_DIR" \
    -Xlinker -rpath -Xlinker "$BIN_DIR" \
    -o "$TMP_DIR/Runner"

"$TMP_DIR/Runner" --testing-library swift-testing
