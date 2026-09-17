# Provider management: behavior and acceptance

macOS and Windows use one Swift core for provider discovery, editing, model discovery, fuzzy search, ordering, configuration writes, authentication refresh, confirmation and account switching. Each native client presents an independent **Add provider** window. See [Provider model setup](provider-model-flow.md) for the complete workflow.

## Setup and authentication

Add saved ChatGPT accounts through the existing sign-in flow. For a custom API provider, open **Manage accounts → Add provider** and enter its name, Base URL and API key, fetch or manually add models, select the models to keep, and choose a default. Saving adds the provider without activating it. A subsequent confirmed switch applies its settings and restarts Desktop.

The installed Codex runtime currently accepts OpenAI Responses as its custom-provider wire format. The form fixes this format and offers no Anthropic selector or discovery. Third-party providers must implement `/responses`; `/messages` or `/chat/completions` alone is insufficient. Fetching models does not establish Responses compatibility. A separate **Verify connection** action sends a short request with the selected model and effort (up to 512 output tokens, possibly billable). It requires completed Responses text output; streaming and tool calls are outside this check.

Previously configured Codex providers remain available through the advanced visibility setting. Their environment or command-based authentication remains owned by Codex. For native OpenAI API sign-in, enter the key in Codex; the switcher discovers the login through `account/read` and retains its file-backed credential separately when a confirmed switch replaces it.

## Configuration and model selection

Saving a managed provider writes its name, base URL, Responses wire format and inline API credential using `config/batchWrite`. It stores selected model IDs, custom order, sorting preference, default model and per-model reasoning effort in the switcher's private `providers.json`, without API keys. Editing the active provider requires switching away first.

When a managed provider is selected, the shared core records the previous provider's effective model, reasoning effort and catalog path. It applies the destination's default model and effort together with `model_provider`, and clears the previous catalog path. Returning to a recorded provider restores its saved selection. An empty effort follows the model default. Effective configuration is read back; profile overrides that prevent the intended selection produce a visible error.

| Destination | Configuration behavior |
| --- | --- |
| Managed provider | Apply its saved default model and reasoning effort; clear the previous model catalog path |
| Recorded native or external provider | Restore its recorded model, effort and catalog path |
| External provider without a recorded selection | Retain current model settings; compatibility must be checked |
| Saved ChatGPT account | Restore saved authentication and select `openai`, with recorded OpenAI model settings when available |
| Native OpenAI API | Restore its separate native credential and select `openai`; ChatGPT and native API share the OpenAI model selection |

Without any managed providers, the existing configured-provider path changes only `model_provider`. The switcher does not generate model catalogs, modify profiles, or inject its selected-model list into Desktop's model picker. The installed Desktop controls picker contents. The normal package uses the installed Codex executable resolved by upstream's runtime locator and does not modify conversations.

Provider and model are separate settings in the [official configuration guide](https://learn.chatgpt.com/docs/config-file/config-advanced#custom-model-providers).

## Native OpenAI authentication

ChatGPT and OpenAI API sign-in both use the built-in `openai` provider. The app reads native login through an app-server session with the read-only override `-c model_provider="openai"`, distinguishing `chatgpt`, `apiKey`, and signed-out states even while a custom provider is active. The override does not change persisted configuration. The account menu refreshes authentication before deciding a selected account is already active.

The OpenAI API row appears when Codex has a native API login or a separate saved API credential exists. Startup does not save the key. A confirmed switch away saves its `auth.json` as `openai-api/auth.json` under local application data. ChatGPT profiles remain under `accounts/<id>/auth.json`. Both use private directories and the existing atomic credential-write path (0700/0600 on macOS, current-user ACLs on Windows). File-backed Codex credentials are required; keychain-only and environment-only API logins are not imported as saved credentials.

After external logout, selecting the same saved ChatGPT account restores its saved credential. Browser login is required if that credential has expired or been revoked. Existing switch failure handling restores the previous authentication kind and provider and attempts to reopen Desktop; failures remain visible.

## Validation and Desktop acceptance

Shared tests cover provider selection, native authentication, model parsing, fuzzy matching, custom and alphabetical order, secret-free snapshots, save failures and model/effort/catalog restoration. Windows checks exercise the actual shared-host model-discovery commands against an isolated HTTP fixture, as well as native controls. These checks use synthetic credentials.

A separate macOS integration probe exercises HTTP discovery, redirect refusal, installed Codex `config/batchWrite`, configuration readback, model/effort restoration and private config permissions in a temporary home. The isolated HTTP fixtures exercise both model discovery and a synthetic Responses validation request. They do not establish stock Desktop acceptance or real-provider inference compatibility.

For acceptance with released Codex Desktop and an authorized provider, record versions, provider IDs, model IDs and outcomes without tokens or full configuration:

1. Start with a saved ChatGPT account, record the new-conversation model and picker choices, and send a harmless prompt.
2. Open Manage accounts and add a Responses provider, fetch models, exercise fuzzy search and ordering, choose its default and an explicitly supported effort, verify the connection, and save. Confirm saving does not activate it.
3. Confirm the switch. Record the model and picker after restart, then send a request. Exercise streaming and tool use when supported by the destination.
4. Switch back to ChatGPT. Verify restored model settings and a successful new request. Repeat with a destination requiring a different model ID.
5. Repeat with native OpenAI API sign-in, then after external logout. Verify the saved native credential and ChatGPT credential remain distinct.
6. Verify an incompatible model, rejected API key, unsupported effort or profile override produces a visible failure; do not substitute a different provider or model silently.

Configuration readback, mocks, UI screenshots and model discovery do not substitute for these real Desktop inference checks.

## Privacy

`config/read` returns the full effective configuration and can include inline credentials in process memory. UI snapshots exclude API keys. The new form keeps the entered key in memory and writes it only to the private Codex configuration when saving. Model discovery sends it only to the entered endpoint and refuses redirects; response bodies are not displayed in errors. The switcher does not independently read environment credential values or invoke provider authentication commands.

Native OpenAI API credentials remain in their separate private local snapshot for later selection. Keys are excluded from UI models, logs, screenshots and PR evidence.
