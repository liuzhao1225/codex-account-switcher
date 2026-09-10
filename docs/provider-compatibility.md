# Advanced provider selection: behavior and acceptance

The feature extends saved ChatGPT account switching with account → configured API provider → saved account transitions. Account switching remains the default experience. Provider selection requires explicit opt-in in Settings on both macOS and Windows. Both clients use the same authentication refresh, selection, confirmation and recovery logic. A configured provider is not evidence of a usable model or successful authentication.

## Setup and authentication

Add each ChatGPT account once through the existing sign-in flow. Configure each API provider, its supported authentication mechanism, and a compatible model in Codex. Verify a successful request in Desktop before selecting it in the switcher. Signing into a provider website alone does not configure API authentication.

Enabling the advanced setting only shows provider choices. It does not sign in, change the current provider, or validate credentials. Credentials remain managed by Codex and the configured provider mechanism, and must be accessible after Desktop restarts. Expired SSO sessions may need to be renewed through the provider's normal login flow. Custom-provider secrets remain in their existing Codex configuration. For native OpenAI API sign-in, enter the key in Codex; the switcher discovers the login through `account/read` and saves its file-backed credential separately when a confirmed switch replaces it.

## Current behavior

The only Codex configuration setting written by the switcher is `model_provider`. Switching native authentication also installs the selected saved `auth.json`. It does not write `model`, reasoning settings, profiles, or model catalogs. The normal package uses the installed Codex executable resolved by upstream’s runtime locator and does not modify conversations.

| Transition | What the switcher changes | What still needs checking |
| --- | --- | --- |
| ChatGPT account to custom provider | Active provider | Retained model ID, model picker contents, authentication, successful request |
| Custom provider to ChatGPT account | Saved account credentials and `openai` provider | Retained model ID and catalog must work with ChatGPT |
| Native OpenAI API to saved ChatGPT account | Save API login separately; restore saved ChatGPT credentials and `openai` | New request must succeed with the retained or manually selected model |
| Saved ChatGPT account to OpenAI API | Save current ChatGPT credentials; restore native API login and `openai` | API access, billing, and compatible model |
| Provider does not support retained model | Provider still changes | Requests may fail until a compatible model is selected/configured |

The Desktop picker is owned by the installed Codex version. This feature cannot guarantee automatic deployment discovery or that a custom model appears. If Desktop exposes a compatible model, select it there. Otherwise configure the model in Codex before using the destination. Returning to ChatGPT does not restore the model or catalog previously used with ChatGPT. Both transition confirmations explain this limitation.

Provider and model are separate settings in the [official configuration guide](https://learn.chatgpt.com/docs/config-file/config-advanced#custom-model-providers).

## Native OpenAI authentication

ChatGPT and OpenAI API sign-in both use the built-in `openai` provider. The app reads the native login through an app-server session with the read-only override `-c model_provider="openai"`, distinguishing `chatgpt`, `apiKey`, and signed-out states even while a custom provider is active. This override does not change the persisted provider. The account menu refreshes that state before deciding a selected account is already active.

The OpenAI API row appears when Codex has a native API login or a separate saved API credential exists. Startup does not save the key. A confirmed switch away from the API login saves its `auth.json` as `openai-api/auth.json` under the switcher's local application-data directory. ChatGPT profiles remain under `accounts/<id>/auth.json`. Both use the existing private directories and atomic credential-write path (0700/0600 on macOS, current-user ACLs on Windows). File-backed Codex credentials are required; keychain-only and environment-only API logins are not imported as saved credentials.

After an external logout, selecting the same saved ChatGPT account restores its saved credential. Browser login is required if the saved credential has actually expired or been revoked; restoring a cached file does not prove remote authorization. Failed transitions restore the actual previous authentication kind (API, ChatGPT, or signed-out), as well as the previous provider, and attempt to reopen Desktop.

## Validation scope

The shared Swift tests and standalone macOS core checks exercise provider selection, native API discovery, API → ChatGPT → API credential restoration, returning to the same saved account after external logout, authentication indicators, and recovery after failed switches. They use isolated fixture credentials and do not make provider inference requests.

Manual reports cover successful use of Azure with Astra, saved ChatGPT accounts with Astra and Sol, and native OpenAI API sign-in. Exact picker inventories, retained model IDs across each restart, and a destination that rejects the previous model ID have not been recorded. These reports support the use case but do not establish seamless model compatibility across providers.

## Desktop acceptance checklist

Use unmodified, released Codex Desktop, a saved ChatGPT account, and an authorized custom provider. Record versions, provider IDs, model IDs and results without recording tokens or full configuration. Use harmless prompts, for example `Reply with OK`.

1. Start with ChatGPT. Record the visible picker choices and selected model in a new conversation. Send the prompt and record a successful response.
2. Enable advanced provider switching and select the configured custom provider. After restart, record the new-conversation selected model and picker choices before changing anything. Send a request using an available compatible model and record any manual configuration required.
3. Repeat with a destination requiring a different model ID. Record the unsupported retained-model behavior; determine whether Desktop permits selecting the working ID or Codex configuration must be edited. Record the successful request after selection/setup.
4. Switch back to a saved ChatGPT account. Record the retained custom model ID and picker contents. If necessary choose/configure a valid OpenAI model, then record a successful response in a new conversation.
5. Sign into Codex with an OpenAI Platform API key. Confirm OpenAI API appears, switch to the same saved ChatGPT account, then back to OpenAI API, and record a successful request at both destinations. Repeat after signing out of the active account.
6. Disable the advanced setting. Confirm provider rows disappear and active provider/configuration remain unchanged. Confirm account switching still works.

Configuration readback, mocks, parser tests, and a visible model-list protocol response do not satisfy these Desktop acceptance steps. Until this run is complete, this feature must not be described as verified seamless switching or ready to merge on that basis.

## Proposed follow-up scope (not implemented)

If seamless switching between different model IDs is required, agree on provider-specific model settings before extending this PR. A proposal should define explicit user selection of a model per provider, restoration of the user's previous OpenAI selection, interactions with profiles and custom catalogs, and atomic application/restoration through supported Codex configuration APIs. Unknown compatibility must remain explicit; do not choose a hardcoded model, infer Azure deployment aliases, inject catalogs, or silently fall back to another provider. Acceptance remains the stock Desktop round trip above.

## Privacy

`config/read` returns the full effective configuration, including inline credentials when present. Those values can enter process memory. The UI retains provider IDs/names, and the switcher does not display, log, or persist custom-provider credentials. Disabling advanced provider UI is not a promise that configuration is never read: account switching also reads it. Codex owns provider authentication; the switcher does not independently invoke its authentication commands.

Native OpenAI API credentials are an explicit exception to custom-provider secret handling: the switcher retains a separate local credential snapshot for later selection. It never includes that key in UI models, logs, errors, screenshots, or PR evidence.

The proposed fetch/select/default-model/reasoning workflow is documented in [Provider model setup](provider-model-flow.md). It remains separate from the implemented cross-platform selection and recovery fixes.
