# Provider, model and reasoning setup

This is the proposed model-management scope following the cross-platform provider fixes. Model discovery, model allowlists and per-destination model/reasoning restoration are not implemented by the current switcher. Current switches retain Codex's model settings; the confirmations explain that limitation.

## Reference workflows

- [Cherry Studio provider settings](https://docs.cherry-ai.com/cherry-studio-wen-dang/en-us/cherry-studio/preview/settings/providers) fetch models through Manage and let the user add individual models to the selectable list. Connectivity checks are a separate operation. [Custom providers](https://docs.cherry-ai.com/cherry-studio-wen-dang/en-us/pre-basic/providers/zi-ding-yi-fu-wu-shang) also support manual model IDs.
- [Open WebUI connections](https://docs.openwebui.com/getting-started/quick-start/connect-a-provider/starting-with-openai-compatible/) discover models when supported and expose a Model IDs filter. Some working chat endpoints have no compatible model-list endpoint. Azure configurations can require explicit deployment names.
- [Cherry Studio reasoning controls](https://github.com/CherryHQ/cherry-studio/blob/main/packages/provider-registry/docs/reasoning-control.md) separate model capabilities from provider request encoding. Supported controls include discrete effort, a token budget, or a toggle. A default choice means omitting an explicit override.

## Proposed user flow

1. Configure or select the connection and its authentication. The existing switcher only selects connections already configured in Codex; adding/editing provider credentials would be additional scope.
2. Fetch the model list on request. Show an explicit error if fetching fails and keep manual model-ID entry available. Fetch success establishes discovery only.
3. Choose which models appear in the switcher's list. Keep upstream model/deployment IDs separate from display names. A switcher allowlist must not be presented as a change to Codex Desktop's own picker.
4. Choose a default model for that destination and the default reasoning setting for that model. Show only capabilities supported by the destination/model; use the model default when no explicit override is selected. Do not assume every provider accepts the same effort vocabulary or token-budget field.
5. Verify a harmless request using the selected model and effort. Report discovery, saved preferences and request verification as separate outcomes.
6. On a confirmed switch, apply the destination's explicit settings together and restore the previous destination's settings on failure. Returning to ChatGPT should restore the prior ChatGPT model/reasoning selection. Preserve existing conversations and their own settings.

## Codex boundary

[Codex app-server](https://learn.chatgpt.com/docs/app-server) exposes `model/list` with `supportedReasoningEfforts` and `defaultReasoningEffort`, and `config/batchWrite` for atomic configuration edits. Use the returned option order. A Codex catalog entry does not by itself establish availability or reasoning support at a particular custom provider; verify that relationship before using it as provider-specific capability data.

For Codex, the settings to investigate together are `model_provider`, `model` and `model_reasoning_effort`. The switcher should not translate arbitrary Anthropic/Gemini thinking parameters independently of Codex's supported protocol. Model changes should revalidate reasoning options. Do not hardcode a universal low/medium/high/max menu or silently substitute an unsupported choice.

The shared Swift core should own discovery results, selected model IDs, validated reasoning options, prepared changes and failure restoration. SwiftUI and WPF should render the same metadata and send the same user actions. Provider-native credential adapters and actual Desktop picker behavior require separate acceptance evidence.
