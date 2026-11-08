# Three-game banner

The complete original design is preserved. Only the playable logos are visible:
Gaiapolis in the upper left (including KONAMI), Mystic Warriors in the center,
and Violent Storm in the upper center, each at its original position and size.
Martial Champion, Metamorphic Force and Monster Maulers remain hidden.

The exact supported three-game artwork and native Pocket banner are retained,
with source/master/export hashes and original slot mapping in
`config/banner-layout.json`. Future playable logos return one at a time to their
original slots. No rearrangement or replacement design is applied.

## Release0.4.0 restoration

Metamorphic Force returns only in its original lower-left slot after Pocket
confirmation; Gaiapolis/KONAMI, Violent Storm and the complete Mystic crest,
lettering and subtitle retain their original slots. Martial Champion and
Monster Maulers remain hidden. The original six-logo master remains preserved.
Built-in image_gen precise-edit prompt: restore ONLY Metamorphic Force from the
lower-left master slot into the existing three-game banner; retain every other
logo/design/position and navy background; no recentering or extra elements.
The generated outer padding is removed, then normalized to521x165 and encoded
with the existing native Pocket encoder; all85965 grayscale pixels roundtrip.
This is a visually reviewed generative restoration, not byte-identical retained
artwork. Source/native hashes are in config/banner-layout.json; physical
appearance of this new four-game presentation is not separately observed.
