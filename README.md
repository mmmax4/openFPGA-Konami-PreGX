# Konami pre-GX — Analogue Pocket openFPGA

![Konami pre-GX: currently playable games](docs/images/banner.png)

A multi-game Konami arcade core for **Analogue Pocket**, by **mmmax4**, based on
[plasticbugs/Scott's Gaiapolis core](https://github.com/plasticbugs/analogue-pocket-gaiapolis).

The goal is to support the games in Konami's pre-GX `mystwarr` hardware family
through one shared core and game menu. **Only Gaiapolis and Mystic Warriors are
currently playable.** The other games below are development goals.

<p align="center">
  <img src="docs/images/gaiapolis-title.png" height="224" alt="Gaiapolis title captured on Analogue Pocket">
  <img src="docs/images/mystic-warriors-title.png" height="224" alt="Mystic Warriors title captured on Analogue Pocket">
</p>

**License:** [GNU GPLv3](LICENSE) for the applicable project code. Original
third-party licenses and notices remain in effect; see [licensing](LICENSING.md).

Some inherited Analogizer dependencies have noncommercial terms. These are
component-specific terms, preserved separately from the project's GPL license.
See [inherited dependency terms](LICENSING.md#inherited-noncommercial-terms).

## Game support

| Game / verified target revision | Current status |
| --- | --- |
| **Gaiapolis (ver EAF)** | **Playable**, tested on Pocket; vertical presentation |
| **Mystic Warriors (ver EAA)** | **Playable**, tested on Pocket; remaining intro graphics defect |
| Violent Storm (ver EAC) | Planned — next game to integrate |
| Metamorphic Force (ver EAA) | Planned |
| Martial Champion (ver EAB) | Planned |
| Monster Maulers (ver EAA) | Planned |

The banner shows the two currently playable games. Each additional logo will
return to its original position when its game becomes playable; see
[banner layout](docs/BANNER.md).

Planned profiles are not exposed as playable selections. Additional revisions
and clones are not automatically supported.

## Current development status

The current hardware snapshot corresponds to **M2 Pocket04**. Pocket testing
reports stable operation. Mystic Warriors' earlier distorted music, incorrect
intro text and split-white transition were corrected in the preceding build;
the current build retains those changes. A remaining defect leaves the five
ninja names red over the scene following their portrait presentation. **That
defect is still open.** A complete Mystic Warriors playthrough was reported on
an earlier development build; it is not a new full playthrough of Pocket04.

The menu provides game selection, separate per-game EEPROM settings/saves,
Test and Service assignments (initially Unassigned), physical board DIP
switches, and display options. Opening the Pocket core-options menu freezes
the game. Mystic Warriors includes a fill-screen option; Gaiapolis keeps its
vertical presentation. The core is grouped under **Arcade Multi**.

Analogizer CRT/SNAC operation has not been physically qualified for these
profiles. EEPROM settings persistence and high-score persistence are separate;
high-score persistence is not claimed.

## Screenshots

Original Pocket captures, exported losslessly at their native orientation.
The Sunset Riders billboard below is a scene **inside Mystic Warriors**.

| Mystic Warriors — gameplay | Mystic Warriors — billboard scene |
| --- | --- |
| ![Mystic Warriors gameplay on Pocket](docs/images/mystic-warriors-gameplay.png) | ![Sunset Riders billboard inside Mystic Warriors on Pocket](docs/images/mystic-warriors-sunset-riders.png) |

## Source and setup

Download [**0.2.0**](https://github.com/mmmax4/openFPGA-Konami-PreGX/releases/tag/v0.2.0),
the ROM-free release using the tested **Pocket04** hardware and two-game banner.
The release includes the Pocket core, ROM builders, corresponding source and
checksums. See [release changes](CHANGELOG.md), [build instructions](docs/BUILD.md),
[ROM setup](docs/ROM_SETUP.md), [validation scope](docs/VALIDATION.md),
[credits](CREDITS.md) and [licensing](LICENSING.md).

Game ROMs, factory EEPROM dumps, saves and private recordings are not included.
Supply the original ROM set for each supported revision. Existing saves should
be retained; this repository does not install or replace them.

Related Pocket projects: [Asterix](https://github.com/mmmax4/openFPGA-Asterix)
and [MooBucky](https://github.com/mmmax4/openFPGA-MooBucky).
