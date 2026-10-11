# Telegram 13 integration validation

Official snapshot: TelegramMessenger/Telegram-iOS `f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838`.
Fork base: `6fd195d294be0a6f5a831b2de5671250faaecbe8`.
Explicit snapshot comparison base: official 12.9.2 `6ad963e5b62d354da79040f388ae2b9132fb17b8`.
The integration commit retains both histories and upstream attribution.

The API is the official generated layer 230 snapshot. The coverage schema is from
Telegram Desktop `6fed91ffab9861771a75f29df65031b3c80b6941`,
`Telegram/SourceFiles/mtproto/scheme/api.tl`.

Fork persistence compatibility retains the existing FlatBuffers union prefixes,
VLESS proxy discriminator 3, old root Web proxy discriminator 2, and the old
hashed passcode formats. New Web proxy paths use a separate discriminator 4.
Managed passcodes use a separate Postbox tag and legacy digest migration requires
successful authentication, preserving cooldown and credential authority.

Camera zoom and recording failure handling move to CameraLegacy with the upstream
camera backend split. Both backends implement the fork zoom protocol.
Fork ghost reads, hidden archive/Saved Messages, customization, BananaGram themes,
branding, and additional settings remain part of regression coverage.

Before pushing to the target branch, run all client regressions and a full IPA
validation build with `create_release=false`. Structural tests on Windows do not
prove Swift type checking or runtime UI behavior. Device checks for theme changes,
proxy transitions, chat visibility, and camera behavior remain necessary.
