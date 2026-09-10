#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir="$project_dir/.build/core-checks"
mkdir -p "$output_dir"

swiftc -emit-module -emit-library -module-name SwitcherCore \
  "$project_dir"/Sources/SwitcherCore/*.swift \
  -emit-module-path "$output_dir/SwitcherCore.swiftmodule" \
  -o "$output_dir/libSwitcherCore.dylib"

swiftc \
  -parse-as-library \
  -I "$output_dir" -L "$output_dir" -lSwitcherCore \
  -Xlinker -rpath -Xlinker "$output_dir" \
  "$project_dir/Sources/CodexAccountSwitcher/DesktopController.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/AppModel.swift" \
  "$project_dir"/Checks/*.swift \
  "$project_dir"/Tests/SwitcherCoreTests/Support/*.swift \
  -framework AppKit \
  -framework SwiftUI \
  -o "$output_dir/CoreChecks"

"$output_dir/CoreChecks"
