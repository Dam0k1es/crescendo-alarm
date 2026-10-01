# Sound credits

All six alarm tones bundled here are from [Mixkit](https://mixkit.co/), under the
[Mixkit Sound Effects Free License](https://mixkit.co/license/#sfxFree). Each file is byte-identical
to the Mixkit preview listed below.

**That licence is not a free licence** (corrected 2026-10-01, `docs/TODO.md` T-212). An earlier
version of this file said its only restriction was reselling a file unmodified; that was wrong. The
licence text says "You can't redistribute the Item on its own, as stock, in a tool or template, or
with source files", and Mixkit's user terms grant only a non-exclusive, terminable licence and
forbid making an item available to third parties. A public source repository and an F-Droid source
tarball do exactly that. These files therefore have to be replaced with freely licensed tones
(CC0, CC-BY or CC-BY-SA) before the app can be submitted to F-Droid; until then they are tracked as
a licence defect, not as accepted.

| File | Mixkit title | Source |
|---|---|---|
| `annoying_alarm.mp3` | Classic alarm | https://assets.mixkit.co/active_storage/sfx/995/995-preview.mp3 |
| `wake_up.mp3` | Alarm clock beep | https://assets.mixkit.co/active_storage/sfx/988/988-preview.mp3 |
| `old_telephone_ring.mp3` | Vintage warning alarm | https://assets.mixkit.co/active_storage/sfx/990/990-preview.mp3 |
| `lollipop.mp3` | Game notification wave alarm | https://assets.mixkit.co/active_storage/sfx/987/987-preview.mp3 |
| `wakeywakey.mp3` | Rooster crowing in the morning | https://assets.mixkit.co/active_storage/sfx/2462/2462-preview.mp3 |
| `wakeywakey2.mp3` | Critical alarm | https://assets.mixkit.co/active_storage/sfx/1004/1004-preview.mp3 |

## Why these replaced the originals (docs/TODO.md T-29)

The six files these replaced (2026-09-17) had no recorded source and, on inspection, turned out to
be exactly the risk T-29 was written against:

- `annoying_alarm.mp3` carried ID3 tags (`title=Annoying Alarm`, `publisher=__KIKO__`,
  `comment=Rate And Subscribe`) consistent with a YouTube-to-MP3 rip of someone else's video, not a
  licensed sound asset.
- `wakeywakey.mp3` and `wakeywakey2.mp3` were both traced to a specific source: the "Wakey Wakey
  it's time for school" internet meme (originally a private family video) as remixed by a YouTube
  user in "Wakey Wakey it's time for scoo Meme (J.JAX Remix)" - neither the original video nor the
  fan remix carries any licence permitting redistribution, and the original traces back to an
  identifiable real person.
- `lollipop.mp3`, `old_telephone_ring.mp3`, and `wake_up.mp3` carried no metadata either way, but
  given the above track record for this asset set, all six were replaced rather than assuming the
  unlabelled three were fine.

The filenames were kept unchanged so no other code (`pubspec.yaml`, `AppState`'s default tone,
`page_alarmtones.dart`, `screen_alarms.dart`, and the several tests that use these paths as fixture
values) needed to change - only the audio content did.
