# Simulator QA evidence

Run the **Simulator QA evidence** workflow from GitHub Actions to build the app for
the iOS Simulator and save first-launch screenshots in light and dark appearance,
plus a short launch recording. The uploaded artifact is retained for 14 days.

The app is launched with its existing `--ui-test` argument. That argument gives
the run a separate temporary data directory and clears it at launch, so no account
or personal chat history is used. This first version covers the real welcome screen;
it does not create a fake logged-in Telegram account or send a message. Authenticated
chat, profile, and settings screens still need an isolated local fixture before they
can be added safely.

## Signed-in screens (2026-11)

After the welcome screens the workflow signs a fresh test-environment number in (`99966 2 YYYY`, code `22222`, no
SMS) and captures the chat list, Saved Messages and Settings in light and dark appearance (`qa-artifacts/screens/`).
Nothing personal is involved: `--ui-test` uses its own data directory and Telegram's test servers.

The app side is three launch flags, honoured only together with `--ui-test`:

- `--ui-test-login <phone>` signs the number in, registering it when new (`test_loginAccount` in TelegramCore), and
  writes `Documents/ui-test-login.done`.
- `--ui-test-keep-data` keeps the test data directory, so later launches find the account.
- `--ui-test-seed` creates three channels with posts and a few Saved Messages (`UITestSeed.swift`), then writes
  `Documents/ui-test-seed.done`. `--ui-test-screen <chats|saved|settings|contacts>` opens that screen after launch.
