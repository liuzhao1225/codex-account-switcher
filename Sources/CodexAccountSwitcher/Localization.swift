import Foundation

enum L10n {
    static func string(_ key: String, language: AppLanguage) -> String {
        let resolved: AppLanguage
        switch language {
        case .system:
            resolved = Locale.preferredLanguages.first?.hasPrefix("zh") == true
                ? .simplifiedChinese
                : .english
        case .english, .simplifiedChinese:
            resolved = language
        }
        return tables[resolved]?[key] ?? tables[.english]?[key] ?? key
    }

    private static let tables: [AppLanguage: [String: String]] = [
        .english: [
            "usage": "Usage",
            "five_hour": "5h",
            "weekly": "7d",
            "usage_unavailable": "Usage unavailable",
            "left": "% left",
            "resets": "Resets",
            "manage": "Manage Accounts",
            "settings": "Settings",
            "quit": "Quit",
            "switch_title": "Switch to %@?",
            "switch_body": "Codex Desktop will close and reopen. A running Desktop task may be interrupted. Existing CLI sessions stay open; new CLI sessions use the selected account.",
            "cancel": "Cancel",
            "switch": "Switch Account",
            "accounts": "Accounts",
            "back": "Back",
            "add_account": "Add Account",
            "remove": "Remove",
            "active": "Active",
            "remove_title": "Remove %@?",
            "remove_body": "This removes only the saved local profile from this Mac.",
            "launch_at_login": "Launch at Login",
            "launch_at_login_requires_approval": "Approval is required in System Settings.",
            "launch_at_login_unavailable": "macOS could not find this Login Item.",
            "open_system_settings": "Open System Settings",
            "show_menu_bar_percentage": "Show Percentage in Menu Bar",
            "show_five_hour_usage": "Show 5-hour Usage",
            "language": "Language",
            "system_default": "System Default",
            "english": "English",
            "simplified_chinese": "简体中文",
            "sign_in_hint": "A browser window will open for Codex sign-in.",
            "no_accounts": "No saved accounts",
            "ok": "OK",
            "operation_failed": "Operation failed",
            "switch_failed": "Account switch failed",
            "active_unconfirmed": "Active account could not be confirmed",
            "switched_reopen_title": "Account switched",
            "switched_reopen_message": "The selected account is active, but Codex Desktop could not be reopened. Open Codex manually to continue.",
        ],
        .simplifiedChinese: [
            "usage": "用量",
            "five_hour": "5 小时",
            "weekly": "7 天",
            "usage_unavailable": "用量暂不可用",
            "left": "% 剩余",
            "resets": "重置于",
            "manage": "管理账号",
            "settings": "设置",
            "quit": "退出应用",
            "switch_title": "切换到 %@？",
            "switch_body": "Codex Desktop 将关闭并重新打开。正在运行的 Desktop 任务可能中断。现有 CLI 会话保持运行，新 CLI 会话将使用所选账号。",
            "cancel": "取消",
            "switch": "切换账号",
            "accounts": "账号",
            "back": "返回",
            "add_account": "添加账号",
            "remove": "移除",
            "active": "当前",
            "remove_title": "移除 %@？",
            "remove_body": "此操作只会移除这台 Mac 上保存的本地账号档案。",
            "launch_at_login": "登录时自动启动",
            "launch_at_login_requires_approval": "需要在系统设置中允许此登录项。",
            "launch_at_login_unavailable": "macOS 找不到此登录项。",
            "open_system_settings": "打开系统设置",
            "show_menu_bar_percentage": "在菜单栏显示百分比",
            "show_five_hour_usage": "显示 5 小时用量",
            "language": "语言",
            "system_default": "跟随系统",
            "english": "English",
            "simplified_chinese": "简体中文",
            "sign_in_hint": "将打开浏览器进行 Codex 登录。",
            "no_accounts": "暂无已保存账号",
            "ok": "好",
            "operation_failed": "操作失败",
            "switch_failed": "账号切换失败",
            "active_unconfirmed": "无法确认当前账号",
            "switched_reopen_title": "账号已切换",
            "switched_reopen_message": "所选账号已经生效，但 Codex Desktop 未能重新打开。请手动打开 Codex 继续使用。",
        ],
    ]
}
