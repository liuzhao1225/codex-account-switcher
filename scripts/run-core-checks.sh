#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir="$project_dir/.build/core-checks"
mkdir -p "$output_dir"

swiftc \
  -parse-as-library \
  "$project_dir/Sources/CodexAccountSwitcher/Models.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/WeeklyUsageNormalizer.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/AccountStore.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/SwitchService.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/DesktopController.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/CodexClient.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/CodexConfigurationClient.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/ProviderSwitchService.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/Localization.swift" \
  "$project_dir/Sources/CodexAccountSwitcher/AppModel.swift" \
  "$project_dir/Checks/CoreChecks.swift" \
  -framework AppKit \
  -framework SwiftUI \
  -o "$output_dir/CoreChecks"

"$output_dir/CoreChecks"
