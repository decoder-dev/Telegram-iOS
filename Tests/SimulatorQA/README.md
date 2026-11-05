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

After the welcome screens the workflow opens an **offline fixture account** and captures the chat list, the Archive,
Saved Messages and Settings in light and dark appearance (`qa-artifacts/screens/`).

Why a fixture: Telegram's test servers no longer provision accounts for random `99966XYYYY` numbers. `auth.sendCode`
still answers, but `auth.signIn` returns PHONE_CODE_INVALID for `XXXXX` on all three test DCs (measured in this
workflow, 2026-11-05; also reported by other clients). So nothing signs in anywhere.

`--ui-test --ui-test-fixture` (`test_createOfflineFixtureAccount` in TelegramCore) writes into the `--ui-test` data
directory what a sign-in leaves behind: an `AuthorizedAccountState` for a made-up user, the record made current, and
eight chats with messages, unread counts and one archived chat. Networking goes to a SOCKS5 proxy on a closed loopback
port with the WebSocket transport and its direct fallback off, so no connection leaves the machine: a server's 401 on
the made-up account would log it out. The chat list therefore shows the connecting state in its title.

Later launches use `--ui-test --ui-test-keep-data`; `--ui-test-screen <chats|archive|saved|settings|contacts>` opens a
screen after launch. `--ui-test-login <phone>` (a real test-DC sign-in) is kept for when test numbers work again.
