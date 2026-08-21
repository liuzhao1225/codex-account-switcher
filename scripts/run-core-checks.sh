#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir="$project_dir/.build/core-checks"
mkdir -p "$output_dir"

swiftc \
  -parse-as-library \
  "$project_dir/Sources/CodexAccountSwitcherLite/Models.swift" \
  "$project_dir/Sources/CodexAccountSwitcherLite/WeeklyUsageNormalizer.swift" \
  "$project_dir/Sources/CodexAccountSwitcherLite/AccountStore.swift" \
  "$project_dir/Sources/CodexAccountSwitcherLite/SwitchService.swift" \
  "$project_dir/Sources/CodexAccountSwitcherLite/DesktopController.swift" \
  "$project_dir/Sources/CodexAccountSwitcherLite/CodexClient.swift" \
  "$project_dir/Sources/CodexAccountSwitcherLite/Localization.swift" \
  "$project_dir/Sources/CodexAccountSwitcherLite/AppModel.swift" \
  "$project_dir/Checks/CoreChecks.swift" \
  -framework AppKit \
  -framework SwiftUI \
  -o "$output_dir/CoreChecks"

"$output_dir/CoreChecks"
