# Release 0.3 validation

## Physical Pocket observations

The tested private candidate and release 0.3 have the same gateware bytes.
Pocket testing reported on 6 November 2026 confirms Gaiapolis, Mystic Warriors
and Violent Storm working. Violent Storm's previously missing sprite rows are
confirmed absent in gameplay and the final attract/demo scene, with second-stage
captures included. The demo capture contains an ordinary transition fade;
that fade is not a reported defect. Mystic's 0.2.1 intro-name workaround remains
enabled. No new full playthrough of these exact bytes is claimed.

[Thirteen lossless Pocket captures](POCKET_0.3.md) illustrate the observed scope.
Release-version, documentation and creator-icon changes do not change hardware.
The new creator Info icon has software format/rotation checks; its appearance
still awaits physical observation.

## Reused source-bound engineering qualification

Hardware snapshot `66a0af551a06eacbfd8bd45c5ff3f20aaf177f03` (fit15):
158 compiled source/constraint/IP inputs plus the generated build-ID MIF.
The curated source reproduces all hashes; three inherited dependencies are
fetched by immutable URL and hash. See PROVENANCE.json and BUILD.md.

All 29 candidate gates passed before Pocket testing. Reviewers were
`verify_mmio` (fit/source/physical SDRAM model) and `verify_profiles` (scripts
and actual candidate archives); native runs and release byte checks were
performed by the lead. Release packaging is checked separately; it does not
claim a new independent RTL review or another compilation.

All four reported timing corners passed. Minimum reported slack in ns:
setup **0.119**, hold **0.107**, recovery **0.906**, removal **2.150**, minimum
pulse **0.520**. The 64 fitted-clock SDRAM cases passed, covering 128 DQ checks;
16 nominal-model diagnostic negatives remain preserved as negatives.
This does not replace the physical Pocket observation or remove documented
clock/model limits. Sprite row/cache response, clip/zoom/line alignment,
contention/deadlines, MMIO controls, reset/game selection and audio received
risk-directed tests using original data. Historical fixtures retain their pins.

Raw RBF SHA256:
`4deaaff48b60f21c2bcc741595d199997bea52cc639c4410eabd7e289e9996d1`.
Pocket bit-reversed RBF SHA256:
`cf040d29a83c32483abedc74e348178f83d455d36888835bdbe87703b25fa059`.

## Limits

Analogizer CRT/SNAC, all multiplayer combinations and high-score persistence
remain separately unqualified. EEPROM settings persistence and high-score
persistence are separate features. No ROM/program/graphics/EEPROM patch was
used. Historical failing evidence and qualified fit data remain archived.
