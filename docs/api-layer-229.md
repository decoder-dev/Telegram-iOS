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

Remaining UI parity work (not claimed complete by the layer upgrade):
- Rich-text callback buttons need a message-aware renderer; currently non-URL buttons retain their labels.
- pageBlockDocument currently maps to the existing unsupported block.
- Unique gift captions/name-hidden fields are decoded by the API; dedicated model/UI support remains to be completed.
- Draft can_stop/keep_on_stop flags are decoded; controls for stopping generated drafts are not implemented here.

The existing v12.9.2-4088-pre tag stays on 37b318a2c1; it does not contain layer 229.
