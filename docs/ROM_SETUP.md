# Original ROM setup

**gaiapols / Gaiapolis (ver EAF)**, **mystwarr / Mystic Warriors (ver EAA)**
and **viostorm / Violent Storm (ver EAC)** are playable selections. Supply your own complete original sets, including their
factory EEPROM members. No program, graphics, sample or EEPROM patch is applied.
The recipe/builders check original sizes/checksums and preserve original data.

Create the ignored working folders and fetch the pinned source references:

```sh
mkdir -p roms private evidence
python3 scripts/fetch_dependencies.py
```

For Gaiapolis:

```sh
python3 tools/mra_build.py gaiapolis.mra /path/to/gaiapols.zip private/gaiapols.rom
```

For Mystic Warriors, place your original `mystwarr.zip` in `roms/`, then run:

```sh
python3 scripts/build_mystic_regions.py
python3 scripts/verify_mystic_regions.py
python3 scripts/build_m2_memory_image.py --regions private/mystwarr-regions --source-manifest evidence/mystwarr-regions.json --rom-zip roms/mystwarr.zip --output private/mystwarr.rom --evidence private/mystwarr-image.json
python3 scripts/verify_m2_memory_image.py --source private/mystwarr-regions --source-manifest evidence/mystwarr-regions.json --image private/mystwarr.rom --builder-evidence private/mystwarr-image.json --rom-zip roms/mystwarr.zip --output private/mystwarr-image-review.json
```

The transport image is reversible; the independent verifier reconstructs and
compares all17 original members. Existing outputs are preserved: use fresh
working paths when repeating the process.

For Violent Storm, place the original `viostorm.zip` in `roms/`, then run:

```sh
python3 scripts/build_viostorm_image.py
python3 scripts/verify_viostorm_image.py --image private/viostorm-m3/viostorm.rom --rom-zip roms/viostorm.zip
```

This uses the frozen MAME 0.289 declarations. The verifier independently recovers
original members from the transport image, checks original CRC/SHA1 and compares
them to the original archive. No original bytes are replaced.

For a release or locally built Pocket package, copy the images to
`Assets/pregx/mmmax4.pregx/gaiapols.rom` and `mystwarr.rom` and `viostorm.rom` on the SD. Copy the
package's Cores, Platforms, Assets and Presets trees to the SD root and open
**Arcade Multi → Konami pre-GX**. Choose one of the three installed games.
Settings use independent `gaiapols.sav`, `mystwarr.sav` and `viostorm.sav` files under
`Saves/pregx/mmmax4.pregx/`. Preserve existing saves; no replacement is supplied.
