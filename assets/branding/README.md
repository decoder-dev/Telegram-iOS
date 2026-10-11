# BananaGram app identity

A broad banana crescent and a folded paper plane form one clean, recognisable mark.
The primary icon uses amber and graphite; 21 coordinated palettes cover warm light, dark and coloured variants.
BlueIcon remains the primary identifier for compatibility with installed alternate-icon selections.

- `*.svg`: editable vector masters, 1024 x 1024; Apple supplies the outer mask.
- `preview.png`: complete palette contact sheet.
- `sizes.png`: all variants at 60, 40 and 29 pixels, shown at their actual size.
- `manifest.json`: shipped PNG paths, pixel dimensions and palette mapping.
- Icon Composer (`Telegram.icon`): the banana and the paper plane are separate opaque layers with system lighting.
  Opacity preserves the silhouette; outer rounded/circular masks are supplied by the system.

Regenerate from repository root with Python 3, Pillow and CairoSVG:

    python tools/branding/generate_icons.py
    python -m unittest discover -s Tests/Branding

Do not rename internal icon identifiers or bundle IDs when changing display names.
Home-screen display name: BananaGram (including localized overrides).
These assets replace app/launcher icons; functional navigation glyphs retain their
existing recognizable semantics.
