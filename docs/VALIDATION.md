# Validation scope

Release 0.2.1 uses the unchanged Pocket-tested intro01 bitstream from frozen
hardware commit `e978e86c1a3d3008949f58293a4faa29ba9ab72d`. Publication updates
corresponding source, documentation, image containers and version metadata;
it does not rerun Quartus or modify that qualified circuit.

The user confirms the ninja-name residue is removed and Mystic Warriors and
Gaiapolis continue to run well. Two actual Pocket intro screenshots show truck
scenes without residual labels, with the normal grey caption retained. No new
full playthrough is claimed. Earlier audio/text/split-white fixes are retained.

The workaround is deliberately specific to the captured EAA scene; the general
hardware rule remains unproven. No game data is patched. See INTRO_WORKAROUND.md.

The new fit has160 timing records across4 corners, nonnegative setup/hold/
recovery/removal/pulse margins and zero TNS. Minima(ns):0.399/0.120/1.147/2.212/
0.520. Resources:14557ALM,22532FF,307/308M10K,45/66DSP.310 normalized warnings
match the preceding qualified fit; no critical warnings. Independent review
covered64 fitted SDRAM cases,128 DQ reports, effective/ignored constraints,
CEN/source-proof scope and432 clock-select paths.16 nominal-model negatives
remain archived as diagnostics, not silently converted to passes.

New workaround evidence:126 component cases;24 paired OFF/ON raster captures
with4,644,864 accepted-consumer comparisons and no missed line deadlines;
367 existing capture samples classified. Raw-DE diagnostic comparisons still
mismatch and are not accepted-production-consumer passes. Unchanged-domain
evidence is reused with original source hashes and explicit finite scope.
Simulation, fit and physical Pocket results are separate.

The older full-machine Pocket03 intro diagnostic ended in a renderer deadline
failure after4391frames; it is not a passing new full-machine integration test.
Name residue preceded its first overrun. MAME reproduces the labels and is not
a correctness oracle for their desired disappearance. Switch Arcade Archives
footage is a separate software comparison rather than a PCB measurement.

Analogizer CRT/SNAC, all multiplayer combinations, exhaustive current-build
full-game regression and high-score persistence remain separately unqualified.
