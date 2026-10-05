# Icon credits

The app icon was created by the maintainer, Dam0k1es, with ChatGPT (OpenAI). OpenAI's terms of use
assign the rights in a generated output to the user who generated it, and the maintainer licenses
the artwork under **CC BY-SA 4.0** (<https://creativecommons.org/licenses/by-sa/4.0/>), recorded on
2026-10-01 (`docs/TODO.md` T-214). Where a jurisdiction grants no copyright in AI-generated images
at all, the artwork is free to use there anyway; the licence then covers the maintainer's own
editing (the cut-outs and variants below).

CC BY-SA 4.0 is one-way compatible with GPLv3, so the icon can ship inside the GPLv3 app. Anyone
reusing the artwork outside it has to credit "Dam0k1es" and share changes under CC BY-SA 4.0.

| File | Title | Author | Source | Licence | Changes |
|---|---|---|---|---|---|
| `icon.png` | Crescendo Alarm app icon | Dam0k1es | generated with ChatGPT (OpenAI) by the maintainer | CC-BY-SA-4.0 | - |
| `icon_no_shadow.png` | Crescendo Alarm app icon, no shadow | Dam0k1es | derived from `icon.png` | CC-BY-SA-4.0 | drop shadow removed |
| `icon_foreground.png` | Crescendo Alarm adaptive-icon foreground | Dam0k1es | derived from `icon.png` | CC-BY-SA-4.0 | scaled into the adaptive-icon safe zone |

The launcher, notification and iOS icons under `android/app/src/main/res/` and
`ios/Runner/Assets.xcassets/` are generated from these files (`dart run flutter_launcher_icons`,
and the notification glyph cut from `icon_no_shadow.png`) and carry the same licence.

## File hashes

The SHA-256 of each shipped file, so a credit row stays tied to the exact file it describes.
`test/media_credits_test.dart` compares these with the files; a replaced file fails until its credit
row has been re-checked and its new hash recorded here.

| File | SHA-256 |
|---|---|
| `icon.png` | `b731e22a4e9b0d19d8a1ea8ebd538a549c0d51e259d4f723cf5b810ca1701399` |
| `icon_foreground.png` | `9bf804c166bb985246ab5831f10b8c4c35eac0964b9247f2660af00828f6b974` |
| `icon_no_shadow.png` | `5e995e61647c1ee676be38d098e1dc31ca516e05ee2690cadc3513ccec794b71` |
