# Hardware and software references

- [Original Gaiapolis Pocket core](https://github.com/plasticbugs/analogue-pocket-gaiapolis),
  pinned base `3cc3ab372331fc5659f81e7c53a5aafff3049e08`.
- [MAME](https://github.com/mamedev/mame): the existing ROM builders retain
  their verified development-source pin `76af2d6d907f0df822dca1d5146454cc5ee18294`.
  Historical tests keep their original source hashes.
- For the next game, audit the latest official stable MAME release before
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
