# Adding a service provider and managing models

macOS and Windows expose a separate **Service providers** window from **Manage accounts → Add provider**. The switching screen only lists existing accounts and providers. The Swift core owns discovery, fuzzy matching, selection, ordering, validation, persistence and applying defaults. SwiftUI and WPF send the same commands.

## Workflow

1. Enter a name, API base URL and key. Use an HTTPS endpoint ending at the API base (usually `/v1`); localhost may use HTTP.
2. The API format is fixed to **OpenAI Responses**. Official OpenAI and third-party Responses-compatible providers are supported. There is no format selector or native Anthropic Messages discovery. Chat Completions-only endpoints cannot be used.
3. Click **Fetch models**. The key goes to the entered origin. Redirects are reported rather than followed with credentials. Failed discovery displays an error; a model ID can also be entered manually.
4. Search by model ID or display name. Matching ignores case, punctuation, width and diacritics, and supports ordered abbreviations such as `g5m` for `gpt-5-mini`.
5. Check the models to enable, choose A→Z, Z→A or custom order, and use the arrows to change the custom order. A search does not alter that stored order. Refreshing preserves selection/order/effort for IDs still returned by the service.
6. Use the star to choose the default model. Set **Thinking / effort** for that model. Empty means the model default. When the service advertises options, they are offered; otherwise a documented service-specific value can be entered explicitly. The app does not infer model capabilities from its name.
7. Optionally click **Verify connection**. It sends a separate `POST /responses` request with the selected model and effort, `store: false`, and a 512-output-token limit; the UI notes possible charges. Only a completed Responses message with text is accepted. Directory responses, Chat Completions responses, errors and incomplete output do not pass. Changing connection details, model or effort clears the prior result. Streaming and tools remain outside this check.
8. **Save provider** writes and reads back the private Codex configuration and stores the model selection/order. It adds the provider without activating it. Editing an active provider requires switching away first.
9. Confirm a provider switch when ready. The switch applies its default model and effort together. Previous provider model/effort/catalog selections are retained for returning to OpenAI. Existing conversations keep their own settings.

The enabled list and its order are the switcher's preferences. They do not replace Codex Desktop's own model picker. Successful discovery and configuration readback do not establish inference or tool-call compatibility; verify those with the actual service.

## Storage and Codex integration

The key is stored in the provider's `experimental_bearer_token` in the local Codex configuration because a GUI-entered key must remain available to Desktop and CLI after restarting. The file is restricted to the current user (`0600` on macOS, a private ACL on Windows). The switcher's `providers.json` contains metadata and model preferences only. API keys are excluded from snapshots and error response bodies are not displayed.

Provider creation uses `config/batchWrite`; selection uses the same API to apply `model_provider`, `model`, `model_reasoning_effort`, and the destination's saved `model_catalog_json` path together. The app reads the result back. It does not manufacture a Codex model catalog or infer Azure deployment IDs. Profile overrides that prevent the effective configuration from matching are reported as failures.

## References

- [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference): Responses is the supported `wire_api`; model selection, reasoning and provider credentials are separate settings.
- [Codex app-server](https://learn.chatgpt.com/docs/app-server): configuration read/write interfaces and model catalog metadata.
- [Cherry Studio provider settings](https://docs.cherry-ai.com/cherry-studio-wen-dang/en-us/cherry-studio/preview/settings/providers): fetching and selecting models; [custom providers](https://docs.cherry-ai.com/cherry-studio-wen-dang/en-us/pre-basic/providers/zi-ding-yi-fu-wu-shang) include manual model IDs.
- [Open WebUI connections](https://docs.openwebui.com/getting-started/quick-start/connect-a-provider/starting-with-openai-compatible/): model discovery and explicit model IDs.
- [Responses request fields](https://github.com/openai/openai-python/blob/main/src/openai/types/responses/response_create_params.py): output limits, storage and reasoning controls.
