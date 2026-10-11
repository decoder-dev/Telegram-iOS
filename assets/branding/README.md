# BananaGram app identity

Glossy vector banana with a Telegram paper plane taking off from its curve, 21 coordinated palettes. BlueIcon remains the primary
identifier for compatibility with installed alternate-icon selections.

- `*.svg`: editable vector masters, 1024 x 1024; Apple supplies the outer mask.
- `preview.png`: complete palette contact sheet.
- `manifest.json`: shipped PNG paths, pixel dimensions and palette mapping.
- Icon Composer (`Telegram.icon`): the banana and the paper plane are separate layers; the plane is Liquid Glass.

Regenerate from repository root with Python 3, Pillow and CairoSVG:

    python tools/branding/generate_icons.py
    python -m unittest discover -s Tests/Branding

Do not rename internal icon identifiers or bundle IDs when changing display names.
Home-screen display name: BananaGram (including localized overrides).
These assets replace app/launcher icons; functional navigation glyphs retain their
existing recognizable semantics.
