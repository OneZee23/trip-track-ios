# TripTrack D2

Vector originals extracted from the user-supplied `TripTrack · Атлас (5).html`:

- `D2.svg`: **D2 · На карте**, the selected primary icon.
- `D-dark.svg`: **D · Модель на креме: режимы iOS → Тёмная**.
- `D-tinted-preview.svg`: the same board's **Тонированная** preview.

The car, palette, scale, shadows, map and route come directly from the design.
The export's `sc-camel-*` attributes are normalized to standard SVG attributes.

Run `python3 Tools/build_app_icons.py` from the repository. Requires Python 3,
Pillow and Google Chrome; `--chrome` accepts another Chromium executable.
The script works offline and renders the vectors at 2048 px before downsampling
to the 1024 px app icon assets. The checked-in PNGs are ready to build; Chrome
and Pillow are not app or Xcode build dependencies.

The script removes the presentation board's rounded mask and edge border:
iOS applies its own mask to the opaque square image. The tinted preview becomes
grayscale because iOS supplies the selected tint
([Apple's asset catalog guidance](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)).
Development builds get a vector `DEV` badge; the Live Activity gets 120 px
light and dark versions of the production icon.
