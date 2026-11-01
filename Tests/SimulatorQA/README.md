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
