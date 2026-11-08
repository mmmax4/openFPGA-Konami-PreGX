# Konami pre-GX — Analogue Pocket openFPGA

<p align="center"><img src="https://raw.githubusercontent.com/mmmax4/openFPGA-Konami-PreGX/v0.4.0/docs/images/banner.png" alt="Konami pre-GX: Gaiapolis, Mystic Warriors, Violent Storm and Metamorphic Force"></p>

A multi-game Konami arcade core for **Analogue Pocket**, by **mmmax4**, based on
[plasticbugs / Scott's Gaiapolis core](https://github.com/plasticbugs/analogue-pocket-gaiapolis).

**Release [0.4.0](https://github.com/mmmax4/openFPGA-Konami-PreGX/releases/tag/v0.4.0)** adds
**Metamorphic Force (ver EAA)**, confirmed working on Pocket with original combat
captures. Gaiapolis0.3.2 graphics/audio improvements, the Violent Storm sprite-row
fixes and Mystic Warriors'0.2.1 intro-name workaround remain included.

## Title screens

<p align="center">
<img src="docs/images/gaiapolis-title.png" height="224" alt="Gaiapolis title screen on Pocket">
<img src="docs/images/mystic-warriors-title.png" height="224" alt="Mystic Warriors title screen on Pocket">
<img src="docs/images/violent-storm-title.png" height="224" alt="Violent Storm title screen on Pocket">
<img src="docs/images/pocket-0.4/metamorphic-force-title.png" height="224" alt="Metamorphic Force title screen on Pocket">
</p>

## Game support

| Game / verified target revision | Status |
| --- | --- |
| **Gaiapolis (ver EAF)** | **Playable, tested on Pocket**; vertical presentation |
| **Mystic Warriors (ver EAA)** | **Playable, tested on Pocket**; intro-name workaround retained |
| **Violent Storm (ver EAC)** | **Playable, tested on Pocket**; horizontal presentation |
| **Metamorphic Force (ver EAA)** | **Playable, tested on Pocket**; horizontal presentation |
| Martial Champion (ver EAB) | Planned |
| Monster Maulers (ver EAA) | Planned |

**Next: the remaining profiles, starting with Martial Champion (ver EAB).**
Martial Champion and Monster Maulers are not playable selections yet.

Only the four playable profiles appear in the game menu and banner. Other
revisions and clones are not automatically supported.

## Install

Download **mmmax4.pregx-v0.4.0.zip** from the
[release page](https://github.com/mmmax4/openFPGA-Konami-PreGX/releases/tag/v0.4.0).
Copy **Cores/**, **Platforms/**, **Assets/** and **Presets/** to the SD root,
merging their contents. **Presets is required** for the correct per-game menu
labels. Keep existing original ROMs and saves. Open **Arcade Multi → Konami pre-GX**.

The SD package contains only those four runtime trees and one README.txt.
ROM builders, source and development documents stay in the repository and the
separate **mmmax4.pregx-v0.4.0-source.zip** download. See
[original ROM setup](docs/ROM_SETUP.md); no ROM, factory EEPROM or save is supplied.

## Features and validation

The shared menu provides game selection, independent per-game EEPROM settings,
Test/Service assignments, actual board DIP switches and display options.
Opening the Pocket core-options menu freezes the game. Gaiapolis retains its
vertical presentation. Mystic Warriors' scene-specific name workaround remains
enabled; [explanation and before/after captures](docs/INTRO_WORKAROUND.md).
No game program, graphics, ROM or EEPROM is patched.

Metamorphic Force is confirmed working on Analogue Pocket. Captures show the
title, combat at multiple locations and the clear message. Gaiapolis' current
vertical character intro is also captured. The earlier three-game Pocket
qualification remains documented separately; no new complete-playthrough or
per-game Mystic/Violent scene coverage is inferred. [Validation](docs/VALIDATION.md).

Analogizer CRT/SNAC and high-score persistence remain separately unqualified.

## In-game screenshots

Gameplay captured on Analogue Pocket, exported losslessly with the original
pixels and orientation. Additional validation captures are in the
[0.4 gallery](docs/POCKET_0.4.md) and [0.3 gallery](docs/POCKET_0.3.md).

<p align="center">
<img src="docs/images/pocket-0.4/metamorphic-force-ruins.png" width="288" alt="Metamorphic Force in-game combat on Pocket">
<img src="docs/images/mystic-warriors-gameplay.png" width="288" alt="Mystic Warriors in-game combat on Pocket">
<img src="docs/images/pocket-0.3/violent-storm-stage2.png" width="384" alt="Violent Storm second-stage in-game action on Pocket">
<img src="docs/images/pocket-0.3/gaiapolis-gameplay.png" height="224" alt="Gaiapolis vertical gameplay after a boss on Pocket">
</p>

## Source and credits

[Changes](CHANGELOG.md) · [Build](docs/BUILD.md) · [ROM setup](docs/ROM_SETUP.md) ·
[References](docs/REFERENCES.md) · [Credits](CREDITS.md) · [Licensing](LICENSING.md)

Applicable project code retains [GNU GPLv3](LICENSE). Original component-specific
terms remain in effect, including inherited Analogizer noncommercial notices;
[their compatibility assessment is unchanged](LICENSING.md#inherited-noncommercial-terms).
Corresponding source accompanies each release. The single SD README contains
required notices and license texts; source keeps its normal license files.

Related Pocket projects: [Asterix](https://github.com/mmmax4/openFPGA-Asterix)
and [MooBucky](https://github.com/mmmax4/openFPGA-MooBucky).
