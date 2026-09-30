# API layer 229 integration

Base: official Telegram Desktop schema pinned in build-system/SwiftTL/api-229-source.md. Official Android reference: dc780e81ed1261c369c27870e8e0999a1eb0b600, TLRPC.LAYER=229.

Implemented:
- Generated Swift codecs and request methods for layer 229; negotiated layer updated from 228.
- Bot reply and inline keyboards use separate typed actions, preserve style, callback payload, force-reply and disabled state.
- Optional ephemeral peer routing, send/delete peer flags and noforwards protection. Welcome templates without a peer are not inserted into arbitrary chat history.
- Community join service action persists the community id and uses a generic localized join notification rather than incorrectly claiming the current user joined.
- Rich-text URL buttons preserve links; button rows preserve labels/URLs.

Validation:
- 2456 schema declarations covered by generated serializers (excluding transport generics/builtins).
- Swift wire round-trip tests and request-layout fixtures in Tests/ApiLayer.
- Full iOS build required in addition to API tests; device validation outstanding.

Follow-up implementation (October 1; full iOS validation pending):
- Rich-text buttons retain typed actions and their wire representation through Postbox/FlatBuffers. Chat taps use the existing message button dispatcher; disabled and streaming-message actions are not invoked.
- Document blocks retain file IDs/captions, render file names/sizes/download progress, and open completed resources in Quick Look with the existing protected-sharing policy.
- Unique gift captions/entities/name-hidden metadata survive storage and original-details mutations. Gift views and service summaries respect hidden sender identity.
- Draft flags control stopping. A successful stop targets the observed generation, retains or removes its content, and blocks late updates. Draft expiration no longer deletes fresh drafts.

Validation additions: production Postbox mutation/expiration tests in Tests/StreamingDrafts. Full iOS compilation and physical-device interaction, accessibility, themes, download failure/retry and Quick Look checks remain required. No claim of complete Android UI parity.

Last verified published baseline: v12.9.5-4093-pre at 95e24fb699ff71dfd7810da8b1a8b923d1b6e586. Follow-up work must not move this tag.
