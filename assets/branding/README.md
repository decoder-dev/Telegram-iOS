# BananaGram app identity

Original vector banana mark, 21 coordinated palettes. BlueIcon remains the primary
identifier for compatibility with installed alternate-icon selections.

- `*.svg`: editable vector masters, 1024 x 1024; Apple supplies the outer mask.
- `preview.png`: complete palette contact sheet.
- `manifest.json`: shipped PNG paths, pixel dimensions and palette mapping.
- Icon Composer uses the same mark as a separate layer.

Regenerate from repository root with Python 3, Pillow and CairoSVG:

    python tools/branding/generate_icons.py
    python -m unittest discover -s Tests/Branding

Do not rename internal icon identifiers or bundle IDs when changing display names.
Home-screen display name: BananaGram (including localized overrides).
These assets replace app/launcher icons; functional navigation glyphs retain their
existing recognizable semantics.
