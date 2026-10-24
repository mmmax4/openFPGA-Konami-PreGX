# Original ROM setup

Only **gaiapols / Gaiapolis (ver EAF)** and **mystwarr / Mystic Warriors (ver EAA)**
are playable selections. Supply your own complete original sets, including their
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

For a locally built Pocket package, copy the images to
`Assets/pregx/mmmax4.pregx/gaiapols.rom` and `mystwarr.rom` on the SD. Copy the
package's Cores, Platforms, Assets and Presets trees to the SD root and open
**Arcade Multi → Konami pre-GX**. Choose one of the two installed games.
Settings use independent `gaiapols.sav` and `mystwarr.sav` files under
`Saves/pregx/mmmax4.pregx/`. Preserve existing saves; no replacement is supplied.
