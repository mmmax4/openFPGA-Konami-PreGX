# Same-family adaptation provenance — 0.3

Copyright (C) 2026 decoryah. Upstream declares GPL-3.0; original terms retained.
Pocket adaptations by mmmax4, October–November 2026. Applicable project terms
remain GNU GPLv3; this does not override component-specific inherited terms.

Violent Storm MiSTer: `decoryah/Arcade-ViolentStorm_MiSTer`, commit
`5865269bc1b149645489a9ad141b4d95097c7530`.

| Original upstream input | SHA256 | Pocket treatment |
| --- | --- | --- |
| K055550 | `1078e0a2a877dfb580bcdeab54f92b8d869e01fc763f67e4c206a2dcbb421b11` | Adapted derivative in rtl/k055550.sv |
| tan128 | `5670ca634548083bbf3864ad8eea93a9e73b5ef86dedde7a3c22944b978a65e2` | Exact bytes in rtl/data/tan128.hex |
| Sprite row-cache reference | `7aed61b69446a718756df0d31dc8eccabfd78889e2924eb433b358f88a48dce6` | Response semantics adapted to Pocket memory/line deadlines |

Gaiapolis Pocket 0.3.2: plasticbugs, commit
`08e2dd4d76911e04a4f12c05db2d88e828258ad3`; ROZ
`932df6b04d3bb34c8eae46cdae16d29c13709249`; audio
`c1a662e6ebc9260dcf907e5e94c989352de9f70b`.
Compared MiSTer lineage: `decoryah/Arcade-Gaiapolis_MiSTer`,
`ebcb5932f4f2e4a7d9d8f02c89dc098e40ce5a15`.
Original plasticbugs, decoryah and component notices are retained. Integration
adapts these changes to the shared Pocket profiles and fitted resource/timing
limits rather than copying MiSTer board timing. Published derived-file hashes
are in docs/PROVENANCE.json; no claim of byte identity is made for derivatives.
