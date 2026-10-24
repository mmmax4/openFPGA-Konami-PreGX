#!/usr/bin/env python3
"""Combined RGB states for previously frozen sprite flip/zoom/mirror/clip cases."""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT.parents[1]


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    source = ROOT / 'tools/m2_mixer_reference.py'
    assert sha(source) == 'df2020d6e43dd7d110702a63d1d63a82f220fd5d5ffa8298b08bbbdb55340c5e'
    spec = importlib.util.spec_from_file_location('frozen_mixer', source)
    ref = importlib.util.module_from_spec(spec); spec.loader.exec_module(ref)
    tile, sprite, rgb = [ref.load_module(n) for n in ref.MODULE_HASHES]
    helper = ROOT / 'tools/m2_mixer_fullshadow_case.py'
    assert sha(helper) == '1051adbca1b9b17deb09378fc9f7a46af069ca1e7e1c3e52b249c3a7bb2ab702'
    spec = importlib.util.spec_from_file_location('frozen_state_parser', helper)
    parser = importlib.util.module_from_spec(spec); spec.loader.exec_module(parser)
    hp = MAIN / 'private/mystic-mixer-oracle/scene-play1800/header.json'
    header = json.loads(hp.read_text())
    assert sha(Path(header['state_path'])) == header['state_sha256']
    parent = parser.parse_state(header['state_path'])
    tr = Path(header['canonical_tile_ROM']).read_bytes(); sr = Path(header['canonical_sprite_ROM']).read_bytes()
    assert hashlib.sha256(tr).hexdigest() == tile.ROM_SHA
    assert hashlib.sha256(sr).hexdigest() == sprite.ROM_SHA
    inputs = {str(Path(p) if Path(p).is_absolute() else MAIN/p):h for p,h in header['inputs_sha256'].items()}
    inputs.update({str(p): sha(p) for p in (Path(__file__).resolve(), helper, hp, Path(header['state_path']))})
    assert all(sha(Path(p)) == h for p, h in inputs.items())
    out = MAIN / 'private/mystic-mixer-geometry'
    out.mkdir(exist_ok=False)
    report = dict(reviewer='lead', scope=__doc__, inputs_sha256=inputs, scenes=[], hardware_verified=False)
    for full in (False, True):
        st = sprite.constructed(parent, full)
        ref.verify_configuration(st)
        packed, summaries, owners = tile.render(st['K56REGS'],st['K55REGS'],st['VRAM'],tr)
        planes_raw = struct.unpack('<'+str(4*ref.W*ref.H)+'H',packed)
        planes = [planes_raw[i*ref.W*ref.H:(i+1)*ref.W*ref.H] for i in range(4)]
        colors, stats, _, order, _ = ref.render(st,planes,sr,sprite,rgb)
        _, _, objects, coverage = sprite.render(st,sr)
        geometry = coverage['geometry']
        assert all(geometry.get(k,0)>0 for k in ('flip_x_tiles','flip_y_tiles','zoomed_tiles','clipped_tiles'))
        wrong = {k:list(v) for k,v in st.items()}
        for obj in range(256):
            off=obj*8
            wrong['SPRITERAM'][off] &= ~0x3000
            wrong['SPRITERAM'][off+4:off+6] = [64,64]
            wrong['SPRITERAM'][off+6] &= ~0xc000
        bad, _, _, _, _ = ref.render(wrong,planes,sr,sprite,rgb)
        differences = sum(a!=b for a,b in zip(colors,bad))
        assert differences>0
        name = 'fullshadow' if full else 'effects'
        folder=out/name;folder.mkdir()
        state=folder/'state.txt';state.write_text(ref.state_text(st,1800))
        pixels=folder/'rgb.bin';pixels.write_bytes(struct.pack('<'+str(ref.W*ref.H)+'I',*colors))
        tile_path=folder/'tile-planes.bin';tile_path.write_bytes(packed)
        h=dict(header)
        h.update(source_kind='constructed_original_ROM_palette_frozen_sprite_geometry_with_original_tile_state',
                 inputs_sha256=inputs,constructed_parent=str(hp),
                 constructed_deltas='Exact unmodified sprite.constructed(parent,full_shadow) from hash-pinned independent sprite oracle; original tile/VRAM/palette unchanged.',
                 objects=objects,global_paint_order=order,statistics=stats,tile_summaries=summaries,page_owners=owners,
                 registers={k:st[k] for k in header['registers']},
                 constructed_checks=dict(geometry=geometry,wrong_no_flip_zoom_mirror_RGB_mismatches=differences),
                 state_path=str(state),state_sha256=sha(state),pixels_path=str(pixels),pixels_sha256=sha(pixels),
                 tile_planes_path=str(tile_path),tile_planes_sha256=sha(tile_path),hardware_verified=False,game_playable=False)
        target=folder/'header.json';target.write_text(json.dumps(h,indent=2)+'\n')
        report['scenes'].append(dict(name=name,header_path=str(target),header_sha256=sha(target),geometry=geometry,
                                    wrong_geometry_pixel_mismatches=differences))
    assert all(sha(Path(p))==h for p,h in inputs.items())
    report['inputs_unchanged']=True
    (out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    (ROOT/'evidence/m2-mixer-geometry-oracle.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report['scenes'],indent=2))


if __name__=='__main__':
    main()
