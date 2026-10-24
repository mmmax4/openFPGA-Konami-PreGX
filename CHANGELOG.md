# Releases

## 0.2.0 — prepared, not publicly released

This version uses the unchanged M2 Pocket04 hardware tested on Pocket. The
public release is pending resolution of inherited Analogizer controller terms
alongside GPL components; the maintainer's noncommercial request does not
resolve that compatibility question.

- Playable: **Gaiapolis (ver EAF)** and **Mystic Warriors (ver EAA)**, selected
  through one shared menu. Other family games remain planned; Violent Storm is next.
- Separate per-game EEPROM settings and saves, Test/Service button assignments
  initially Unassigned, board DIP switches and pause in the core-options menu.
- Mystic Warriors fill-screen option; Gaiapolis vertical presentation retained.
- Earlier Mystic audio distortion, intro lettering and split-white transition
  fixes are retained. Known issue: the five ninja names can remain red after
  their portrait presentation.
- Updated banner shows only the two playable games; original positions are
  reserved for later supported games. Pocket screenshots remain in the README.
- ROM-free package prepared with both ROM builders, inverse checks, notices
  and corresponding source. No game ROM, factory EEPROM dump or save is bundled.

Only release labels and packaging metadata use the number 0.2.0; Pocket04
remains the technical identifier for the tested circuit. No new fit or physical
Analogizer qualification is claimed. See [validation scope](docs/VALIDATION.md)
and [licensing](LICENSING.md).

## Development history

### M2 Pocket04 — current source snapshot

- Mystic sprite-copy timing aligned with the reviewed blanking/enable trigger.
- K055555/K054338 brightness integrated before alpha; shadows remain separate.
- Existing three-stage RGB latency retained with a fitted brightness pipeline.
- Pocket feedback: stable operation; ninja-name residue remains open.

### Earlier development

- Gaiapolis baseline retained while adding playable Mystic Warriors.
- Separate game selection, settings/saves, physical DIP switches and controls.
- Optional Test/Service assignments and Pocket-menu freeze/resume.
- Mystic music, lettering and split-white intro fixes; fill-screen option.
- Shared memory/renderer work, user banner and Arcade Multi presentation.

Violent Storm is next; the remaining family profiles are planned.
