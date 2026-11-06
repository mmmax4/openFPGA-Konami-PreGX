# Pocket creator icon

The Info icon uses the [mmmax4 GitHub avatar](https://github.com/mmmax4), converted
into the official [openFPGA author graphic format](https://www.analogue.co/developer/docs/openfpga/packaging-a-core).
It is 36×36, black and white, 16-bit little endian with brightness in the upper
byte, stored 90° counterclockwise. The original green dot becomes white.

![Upright icon preview](images/creator-icon-preview.png)

`tools/pocket_author_icon.py` reproduces the conversion from
`docs/images/creator-avatar.png`. Hashes and method are in
`config/creator-icon.json`. Binary size, brightness and inverse rotation are
checked in software; the new Info presentation awaits physical observation.
Original gateware authors remain credited in CREDITS.md and source notices.
