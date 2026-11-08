# Release0.4.0 validation

Metamorphic Force EAA is confirmed working on Analogue Pocket on8November2026.
The original captures show title, intro, combat in ruins and a temple, a colour
effect and a YOU'VE DONE IT! message. No bug was reported. This is observed
scene/gameplay coverage, not a new complete-playthrough, all-multiplayer or
save/reset qualification. A vertical Gaiapolis character intro was also captured.
The earlier three-game [Pocket qualification](VALIDATION_0.3.md) remains historical;
the general current-core confirmation does not supply new per-game Mystic/Vio scenes.

Gateware is byte-identical to the tested m4p01 candidate. Source commit
`6c40292c70740833dd1e39455143e515b05a4d5a`:162 compiled inputs plus generated MIF;
three unchanged external Analogizer dependencies fetched by immutable SHA256.
All four timing corners and160 records pass: minimum setup0.004ns, hold0.116ns,
recovery0.895ns, removal2.039ns and pulse0.520ns. Setup margin is very small.
18021/18480ALM,1844/1848LAB,308/308M10K. No ignored SDC or Critical Warning.
98 fitted adapter FFs stay outside DSP inputs; sound selectors use standard-cycle
constraints. No clock or CPU timing exception was copied to new M4 logic.

64 fresh fitted-envelope SDRAM model executions pass with5248 original-word
observations, actual AS4C32M16MSA-6BIN CL3/10410ps, startup/MR/EMR/tAC/tOH/tHZ/X/Z
and clock checks. This qualifies the read-capture model scope, not a physical
memory aperture measurement. Native runs: lead; independent SDRAM/actual private
archive review: research_metam. Earlier source/component reviews retain their
actual authors. Publication byte/notice checks are separate lead checks.

Scoped source-bound evidence is reused for original loader/MMIO/IRQ, shared RAM,
PSRAM road state/commit, pixels/priority/zoom/deadlines, original audio traces,
EEPROM/reset/unload and unchanged games. Changed timing-repair risks received
selected fresh component checks. Four original PNG consumer comparisons cover
258048 pixels; current audio checks cover25952 stereo comparisons/54.5M clocks.
Historical raw-getter negatives and conditional road-shadow1/2 limits remain
recorded. A200M-clock startup simulation stayed in self-test/blank; no complete
native original-program pass is claimed. Actual Pocket confirmation is distinct.

Analogizer CRT/SNAC, all multiplayer combinations and high-score persistence
remain separately unqualified. No program/ROM/graphics/EEPROM patches are used.
Raw RBF: `d070e465f893c315263b0b686d4e9c7f71242470ac45e40708a57eef09fccf58`.
Pocket RBF: `6f4616f68726b71b4c2afbba121b1166c9990eafceb500e6c4dd45146bbabe16`.
Release metadata and four-game banner do not require a new fit. The newly
restored banner's physical appearance is not separately observed.
