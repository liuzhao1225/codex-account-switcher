import Foundation

struct ConfigScriptFixture {
    let root: URL
    let executable: URL
    let marker: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "codex-provider-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        executable = root.appending(path: "fake-codex")
        marker = root.appending(path: "provider-selected")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\\n' '{"id":0,"result":{}}' ;;
            *config*read*)
              if test -f '\(marker.path)'; then
                printf '%s\\n' '{"id":1,"result":{"config":{"model_provider":"openai","model_providers":{"azure":{"name":"Azure OpenAI"}}},"origins":{}}}'
              else
                printf '%s\\n' '{"id":1,"result":{"config":{"model_provider":"azure","model_providers":{"azure":{"name":"Azure OpenAI"},"local_proxy":{}}},"origins":{}}}'
              fi
              ;;
            *config*value*write*)
              : > '\(marker.path)'
              printf '%s\\n' '{"id":1,"result":{"filePath":"/tmp/config.toml","status":"ok","version":"1"}}'
              ;;
          esac
        done
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
