# Banner and game support

The current banner shows **Gaiapolis** and **Mystic Warriors** in their original
positions. Violent Storm, Martial Champion, Metamorphic Force and Monster Maulers
are hidden while those profiles remain planned. The remaining logos are not
recentered or enlarged to fill the vacated slots.

The complete user-supplied design master is preserved by the maintainer, bound
by SHA256 in config/banner-layout.json. Restore each newly playable game's logo
from that master at its original slot and size, leaving pending games hidden.
The fixed slots are upper-left(Gaiapolis), center(Mystic Warriors), upper-center
(Violent Storm), upper-right(Martial Champion), lower-left(Metamorphic Force)
and lower-right(Monster Maulers).

The edited521x165 source is docs/images/banner.png. Re-encode a source with:

```sh
python3 tools/encode_pocket_banner.py docs/images/banner.png private/banner/pregx.bin --preview private/banner/preview.png
```

The encoder changes only storage/grayscale format, checks every pixel on the
roundtrip and refuses existing output files. The Pocket asset is
pkg/pocket/Platforms/_images/pregx.bin. Artwork changes do not qualify a new
hardware build or additional games.
