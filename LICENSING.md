# Licensing

This is a mixed source tree. The upstream Gaiapolis project declares GNU GPLv3;
the [top-level GPLv3 text](LICENSE) covers applicable project code and mmmax4's additions.
Original per-file terms and copyright notices remain authoritative. Scott's
reuse/derivative-core permission is summarized in LICENSES/PLASTICBUGS-PERMISSION.md.

TG68K.C carries LGPL-3.0-or-later; its original VHDL and synthesis recipe accompany
the generated Verilog. TV80 carries MIT terms. OpenGateware and adapter files
retain their MIT, GPL, CC0 and other original notices. Analogue platform and
Intel generated-IP/device restrictions apply to their respective files. No
proprietary Quartus tool libraries or tool executables are distributed.

## Inherited noncommercial terms

Three inherited Analogizer dependency files are obtained directly from their
pinned upstream rather than redistributed here: `dualshock_controller.v`,
`debounce.vhd` and `ps2_keyboard.vhd`. The DualShock file has a noncommercial-use
notice; the Digi-Key VHDL files retain their original notices. Their inclusion
in a third-party repository is not treated as a blanket GPL grant. Paths,
immutable URLs and exact expected hashes are in config/dependencies.json.
See docs/BUILD.md. These are terms of the inherited components, not a general
noncommercial license for this project. Keeping their notices does not by itself
resolve compatibility with GPL components in a compiled release; that release
still needs its own redistribution review.

The user-supplied banner/icon and requested Pocket screenshots are presentation
assets, separate from the software license. Game artwork, names and characters
remain their respective owners' works. No game ROM, EEPROM dump, save, video,
private message or permission screenshot is included.
