# Hardware and software references

- [Original Gaiapolis Pocket core](https://github.com/plasticbugs/analogue-pocket-gaiapolis),
  pinned base `3cc3ab372331fc5659f81e7c53a5aafff3049e08`.
- [MAME](https://github.com/mamedev/mame): the existing ROM builders retain
  their verified development-source pin `76af2d6d907f0df822dca1d5146454cc5ee18294`.
  Historical tests keep their original source hashes.
- For each new implementation phase, audit the latest official stable MAME release before
  implementation, then freeze its tag, commit and relevant file hashes for that
  phase. On 24 October 2026 the latest official stable release was
  [0.289](https://github.com/mamedev/mame/releases/tag/mame0289), commit
  `f34f02505e32c1993c6a782b6814232cbfc74e36`. It predates the development pin
  above, so "latest stable" does not imply every development change is present.
- [furrtek/SiliconRE](https://github.com/furrtek/SiliconRE), indexed at commit
  `c926ce92fdebd7613c8712b42c45a059d63548e0`, provides silicon reverse-engineering
  material. Completeness and applicability must be checked per chip. The author
  states GPL-2.0 and restrictions concerning AI generation; no SiliconRE HDL,
  schematics or die traces are imported into this core by this update.

References document behavior and hypotheses; they do not replace physical
Pocket testing. MAME can reproduce an imperfection, and a reconstructed chip
model can be incomplete. Distinguish measured evidence, software models and
declared compatibility workarounds. Original licenses remain applicable.

## Violent Storm and Gaiapolis 0.3.2

Available same-family MiSTer sources were compared before adapting hardware;
Pocket memory, cache-response, timing and line-deadline contracts are preserved.

- [decoryah / Violent Storm MiSTer](https://github.com/decoryah/Arcade-ViolentStorm_MiSTer),
  commit `5865269bc1b149645489a9ad141b4d95097c7530`: K055550 behavior and tangent
  table; sprite row-cache response contract studied and adapted. K055550 is a
  Pocket derivative; only `tan128.hex` is byte-identical to its upstream file.
- [plasticbugs Gaiapolis](https://github.com/plasticbugs/analogue-pocket-gaiapolis),
  0.3.2 tree `08e2dd4d76911e04a4f12c05db2d88e828258ad3`; ROZ change
  `932df6b04d3bb34c8eae46cdae16d29c13709249`; audio change
  `c1a662e6ebc9260dcf907e5e94c989352de9f70b`.
- [decoryah / Gaiapolis MiSTer](https://github.com/decoryah/Arcade-Gaiapolis_MiSTer),
  compared tree `ebcb5932f4f2e4a7d9d8f02c89dc098e40ce5a15`.
- Violent Storm uses frozen official MAME **0.289**, commit
  `f34f02505e32c1993c6a782b6814232cbfc74e36`, audited at phase start.
  Driver `src/mame/konami/mystwarr.cpp` SHA256:
  `f6c1ba57e7522803c48b3437e51744ecae3183d4be725d7a7b93c20e2d49199a`.
  Historical Mystic builder/oracle pins remain unchanged. Publication does
  not restart that implementation phase or silently upgrade its reference.

Original import hashes and the published derived-file hashes are recorded in
LICENSES/DECORYAH-PROVENANCE.md and PROVENANCE.json. No SiliconRE content is
imported by release 0.3.

## Metamorphic Force0.4.0

- MAME stable0.289, `f34f02505e32c1993c6a782b6814232cbfc74e36`, original EAA declarations; historical pins preserved.
- decoryah/Arcade-MetamorphicForce_MiSTer, `879420178efb2e632e140c51311f1ffe72caaa31`: GPLv3 K053250 source, original tests, README and notices retained under `upstream/metamorphicforce-87942017/`.
- Pocket derivative adds bounded scheduling, shared line/video RAM, explicit external road-state/PSRAM ownership and fitted timing repairs; MiSTer clocks/DDR/HPS/timing exceptions are not imported.
- Source headers retain the development archive location as provenance; the public original-source counterpart is the `upstream/` directory above.
- SiliconRE catalog was considered; no HDL or schematics imported from it.
