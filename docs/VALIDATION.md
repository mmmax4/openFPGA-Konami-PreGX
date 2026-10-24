# Validation scope

The current source corresponds to frozen candidate16 hardware
`ee302eaa74ac31f3bc770bb76999eb68b82e25b0` and the Pocket04 development package.
Publication changes documentation, asset containers and packaging metadata;
it does not change hardware RTL or fitted constraints.

The user reports Pocket04 stable and functioning; intro/gameplay screenshots
were supplied for Mystic Warriors and a title capture for Gaiapolis. Mystic's
five red ninja names remain after the portraits. Earlier Pocket03 testing
confirmed improvements to distorted music, intro lettering and the split-white
effect. An earlier Mystic build was played through to completion; this is not
a new full playthrough of Pocket04 or exhaustive per-game qualification.

Candidate16's160 timing records have nonnegative setup/hold/recovery/removal/
pulse margins and zero TNS. Minima(ns):0.364/0.076/1.116/2.149/0.520.
Resources:14593ALM,22438FF,307/308M10K,45/66DSP. The310 warnings match the
previous qualified fit's normalized warning set, with no critical warnings.
Separate fit/SDRAM reviews covered128DQ reports and64fitted capture cases.

Fresh brightness-pipeline checks include12rendered frames and2322432 acceptance
pixel comparisons, plus arithmetic, selector, RGB-line and sprite-DMA checks.
Unchanged-domain evidence is reused only with its original source hashes and
scope. Simulation, fit and physical Pocket observations are separate evidence.

A separate complete-machine **older Pocket03** intro diagnostic ended with a
renderer deadline failure after4391frames (unsupported0; overrun high-sample
counter245760). This is not a passing full-machine integration test or a new
Pocket04 physical failure. The first persistent labels occur before its first
overrun. MAME also reproduces the labels and is not a correctness oracle for
their expected disappearance. Switch Arcade Archives footage supplied by the
user provides a separate visual comparison, not a PCB trace.

Analogizer CRT/SNAC, all multiplayer combinations, full-game regression of the
current build and high-score persistence are not claimed as qualified.
