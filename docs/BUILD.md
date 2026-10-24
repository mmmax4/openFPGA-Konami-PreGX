# Build

The hardware snapshot is the source used for the intro01 compatibility17 fit.
Quartus Prime Lite **21.1.1**, Cyclone V support and Python 3 were used. No new
Quartus build is claimed for this publication. Device settings, clock IP,
constraints and generated CPU source are retained. Do not copy timing exceptions
to a different architecture without reviewing their actual enable phases.

Fetch the pinned external dependencies first:

```sh
python3 scripts/fetch_dependencies.py
bash scripts/build.sh compile
```

The fetcher verifies SHA256 before writing each dependency and refuses changed
existing files. Three inherited Analogizer files are deliberately obtained from
their original upstream; their terms remain applicable. MAME references are
needed by the ROM builder/verifier, not by Quartus. These fetched files are
gitignored; no ROM or save is downloaded.

The output raw bitstream is `projects/output_files/gaia_pocket.rbf`. To prepare
a local Pocket folder from a successful build:

```sh
python3 scripts/package_local.py --rbf projects/output_files/gaia_pocket.rbf
```

This writes `private/pocket-local` once, reverses each bitstream byte for Pocket,
and uses the checked package-file allowlist. It does not include game ROMs or
saves. Follow ROM_SETUP.md before use. This local helper is not a public binary
release and does not establish hardware qualification for a new fit.

The pre-flow Tcl generates a date/time/random build identifier; the retained
intro01 MIF records the tested build, while recompilation generates a new one.
Bit-identical rebuilds are not promised. TG68K's original VHDL, generated Verilog
and GHDL synthesis recipe are included; the inherited conversion used GHDL6.0.

Original simulation sources and functional lookup-table generators are retained.
Game snapshots, audio traces and reference captures needed by some tests remain
private and must be acquired from original data. A missing fixture or zero
executed comparisons must not be interpreted as a passing test.

The historical mixer comparison additionally requires GAIAPOLIS_REFERENCE_MIXER
pointing to the original mixer at the base upstream commit, a timing-capable
Verilator (VERILATOR or PATH) and a C++20-capable compiler/wrapper (CXX). Its
public helper has portable paths; no fresh mixer simulation is claimed here.

The released Quartus project explicitly defines `MYSTIC_INTRO_COMPAT=1`, matching
the Pocket-tested bitstream. The reusable module parameter defaults to zero.
To build a diagnostic without the workaround, remove that QSF macro assignment;
the current `ifdef` tests macro presence, so defining it as `=0` does not disable
it. A changed build has its own validation scope. See INTRO_WORKAROUND.md.

The added `sim/tb_m2_names_compat.cpp` and `_top.sv` retain the component test
logic. Their executed four-way comparison used an archived unmodified object
list (module name changed only), original private scene snapshots and expected
draw orders. Those game captures are not bundled, so this source archive alone
does not claim a new runnable-fixture or test pass.
