# Known surprises

- The macOS runtime locator uses the login shell's `CODEX_CLI_PATH` or `codex` from its `PATH`. An executable npm launcher can still fail with `spawn ... ENOENT` when its platform binary is missing. A successful Swift build or app launch does not validate this dependency: verify the resolved CLI's `--version` and a harmless app-server configuration read before handing over an installed test build.
- Switching from a locally bundled runtime to upstream runtime discovery can expose a previously unused, broken global CLI installation. Repair that installation using its supported package manager; keep that machine repair separate from provider-switching source changes.
- `config/read` may include inline credentials. Runtime verification must report only selected metadata, never full configuration or credential values.

- Native OpenAI API-key sign-in still uses `model_provider = "openai"`; `account/read` distinguishes `apiKey` from `chatgpt`. A cached account ID or provider ID alone cannot determine the active login. Refresh authentication before deciding that clicking a saved account is a no-op, and keep the native API credential snapshot separate from saved ChatGPT profiles.
- Inspect native authentication under a read-only app-server `-c model_provider="openai"` override when a custom provider is active. This does not change the on-disk selection and avoids mistaking a custom provider's empty account response for a logged-out native account.
