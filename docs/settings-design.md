# Settings visual consistency · v0.1.10

Settings retains the native 326-point popover and shared back header. General preferences and Software Update use the same 13-point system text, 14-point horizontal insets, minimum 44-point rows, small native controls, and aligned right edge. Group captions and descriptions use 11-point system text. Separators align with the labels. Approval and update errors wrap below their associated row.

The automatic-update setting uses the same switch layout as the other preferences. Its description states the hourly schedule and blue-dot reminder. The version and Check for Updates button occupy a matching setting row. Existing actions and persistence bindings remain in place.

Verification used the production SettingsView in isolated native previews. Chinese and English, light and dark, each render at 326 × 392 points in the normal state without truncation; the unavailable-login-item state also wraps correctly. Native accessibility interaction confirmed the 5-hour toggle, language change, and automatic-update toggle update immediately. Test account settings use a temporary directory; login-item status is supplied by the preview fixture, so these checks do not register a real Login Item.

Local rendering evidence is in `.build/settings-visual/after/`; the before snapshot and native preview harness are retained alongside it. Preview-harness lifetime and event-loop issues were corrected during verification and do not enter the application. Full CI remains required before creating the release tag.
