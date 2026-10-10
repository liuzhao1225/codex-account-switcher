import Foundation

enum DesktopLaunchEnvironment {
    static func parse(_ text: String) -> [String: String] {
        var environment: [String: String] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            guard
                !line.isEmpty,
                !line.hasPrefix("#"),
                let separator = line.firstIndex(of: "=")
            else {
                continue
            }

            let key = String(line[..<separator])
                .trimmingCharacters(in: .whitespaces)

            guard !key.isEmpty else {
                continue
            }

            let valueStart = line.index(after: separator)
            let value = String(line[valueStart...])

            environment[key] = value
        }

        return environment
    }
}
