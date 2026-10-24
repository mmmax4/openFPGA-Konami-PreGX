# Vendored modules

Third-party HDL provenance from the upstream snapshot. Original per-file
notices apply. The public snapshot obtains three Analogizer dependencies
directly from pinned upstream URLs; see LICENSING.md and config/dependencies.json.

| module | upstream | via | licence |
|---|---|---|---|
| cpu-tg68k | https://github.com/TobiFlex/TG68K.C @ ade33e396a1e647c2de9daf71ff9d5b3979639b2 | plasticbugs/analogue-pocket-stunrunner (ghdl-converted `gen/tg68k.v`) | LGPL-3.0 (the .vhd headers; "change GPL to LGPL", 04.04.2017) |
| cpu-tv80 | https://github.com/hoglet67/tv80 (Guy Hutchison's tv80) | plasticbugs/punchout, with its `tv80s_cen.v` clock-enable wrapper | MIT |
| `target/pocket/analogizer/` | RndMnkIII's Analogizer adapter module (`openFPGA_Pocket_Analogizer` 1.4) and the 14 files it instantiates, verbatim, from https://github.com/RndMnkIII/MiraxPocket `src/fpga/analogizer/` @ 9dfdd2b9bec79fe5ea10e154a0613a0c9d4fe37f; `analogizer.qip` is ours | plasticbugs/pocket-core-template (9233037) | Mixed original per-file terms (three external dependencies; see LICENSING.md); `hq2x.sv`, `scandoubler_2.v`, `yc_out_legacy.sv` carry their own GPL headers |

The Analogizer module lives under `target/pocket/` rather than `modules/`
because it is the Pocket's cartridge port, not the machine: `core.qip`
includes its own `analogizer.qip`, and `sim/lint.sh` lints it behind
`target/pocket/pocket_analogizer.sv` (the template's wrapper, unchanged)
with a stand-in for its one VHDL file (`sim/ps2_keyboard_stub.v`). Left out,
as in the template: `scandoubler.v`, `scanlines.v`, `yc_out.sv`,
`psPAD_top.v`, `psx_control.v`, `csync.v`, `sync_fix.v` (also defined inside
the top file), `two_button_press_detector.v`, `uart_tx.v` and
`sine_lut.mem` -- nothing instantiates them.

**Local change** (the only one): `openFPGA_Pocket_Analogizer.v` gains
parameters `USE_YC` and `USE_SD`, default 1, which is RndMnkIII's 1.4
exactly. Off, generate blocks leave out the Y/C encoder, or the scandoubler
with its HQ2x and VGA scanlines, tie their outputs to the pass-through
values, and map their video modes to RGBS. Each edit is marked `LOCAL`, with
a note under the untouched header; it is the same change as in plasticbugs'
S.T.U.N. Runner core (48e09cb). This core builds with `USE_SD = 0`: the
scandoubler's line buffers are block RAM it does not have.

Not vendored, and why: jotego's `jt539` (K054539) is referenced by jtcores as a
submodule but the repository is not public (404), so the K054539 is written
here from MAME's `k054539.cpp`. See docs/prior-art.md.

To update one: re-copy from upstream at the new commit and record it here.

## Konami pre-GX local compatibility change

`target/pocket/analogizer/yc_out_legacy.sv`: declare the immutable signed
256-entry chroma sine table as `localparam` instead of a net-array initializer.
This permits Verilator 5.040 to parse the encoder; the values, signed width,
indices and encoder timing remain identical. See the in-file `LOCAL` note.
