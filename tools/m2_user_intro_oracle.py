#!/usr/bin/env python3
"""Original captured states through unchanged current-source RGB models.

Historical MAME pixels and the user's screenshot are not read as golden data.
Outputs are private, source-bound static-state renderer inputs, not gameplay.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys
import zlib

sys.dont_write_bytecode = True
WORK = Path(__file__).resolve().parents[1]
ROOT = WORK.parents[1]
MIXER_SHA = 'df2020d6e43dd7d110702a63d1d63a82f220fd5d5ffa8298b08bbbdb55340c5e'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def png(path, colors, width, height):
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff)
    raw = b''.join(b'\0' + b''.join(bytes((v >> 16 & 255, v >> 8 & 255, v & 255)) for v in colors[y*width:(y+1)*width]) for y in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', type=Path, default=WORK/'private/mystic-user-intro-oracle')
    ap.add_argument('--capture', type=Path, default=WORK/'private/mystic-capture/user-attract04')
    ap.add_argument('--frame', type=int, action='append', help='Original frame; repeat for multiple scenes')
    args = ap.parse_args()
    out = args.output.resolve()
    need(not out.exists(), 'Preserve existing oracle; use a fresh output')
    model_path = WORK/'tools/m2_mixer_reference.py'
    need(sha(model_path) == MIXER_SHA, 'Unchanged independent mixer model required')
    spec = importlib.util.spec_from_file_location('intro_mixer_reference', model_path)
    mixer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mixer)
    tile, sprite, rgb = [mixer.load_module(name) for name in mixer.MODULE_HASHES]
    sources = dict(sprite.SOURCES)
    sources.update({'ref/mame/'+name: value for name, value in tile.SOURCES.items()})
    sources.update({'private/mame0220/current_drawgfx.h': rgb.SOURCES['private/mame0220/current_drawgfx.h'],
                    'private/mame0220/current_dipalette.cpp': '58343b1dc046faf0d3d28ec0b760ea0850bf74a28a7044bff2dc4ef4d923d248'})
    paths = [Path(__file__).resolve(), model_path, *(WORK/'tools'/name for name in mixer.MODULE_HASHES)]
    for rel, digest in sources.items():
        p = ROOT/rel
        need(sha(p) == digest, 'Pinned normative source changed: '+rel)
        paths.append(p)
    tp, sp = ROOT/'private/mystwarr-regions/k056832.bin', ROOT/'private/mystwarr-regions/k055673.bin'
    need(sha(tp) == tile.ROM_SHA and sha(sp) == sprite.ROM_SHA, 'Original canonical graphics identity')
    paths.extend([tp, sp])
    vector = ROOT/'private/m2-rgb-oracle/vectors.txt'
    need(sha(vector) == 'c9a2458fc7dad0e2edd49f69bbc85635f5acda3cf55bdff016ecf96b6c977efd', 'Frozen RGB vectors changed')
    scalar_checks = 0
    for line in vector.read_text().splitlines():
        src, dst, level, is_tile, expected = [int(v, 16) for v in line.split()]
        need(rgb.evaluate(src, dst, level, is_tile) == expected, 'Frozen RGB scalar crosscheck')
        scalar_checks += 1
    need(scalar_checks == 6726, 'RGB vector count')
    paths.append(vector)
    frames = args.frame or [4140]
    need(len(set(frames)) == len(frames) and all(0 <= frame <= 99999 for frame in frames), 'Unique captured frame numbers required')
    capture = args.capture.resolve()
    output_hashes = {Path(line.split()[1]).name: line.split()[0] for line in (capture/'outputs.sha256').read_text().splitlines() if line.strip()}
    fields = {'K46REGS': ('k46_regs', '<8B'), 'K47REGS': ('k47_regs', '<16H'),
              'K55REGS': ('k55_regs', '<128B'), 'K38REGS': ('k38_regs', '<32H'),
              'SPRITERAM': ('k47_list', '<2048H'), 'K56REGS': ('k56_regs', '<32H'),
              'K56REGSB': ('k56_regsb', '<4H'), 'VRAM': ('k56_vram', '<69632H'),
              'PALETTE': ('palette', '<4096H')}
    paths.extend(capture/name for name in ['outputs.sha256', 'inputs.sha256', 'parameters.txt', 'version.txt'])
    out.mkdir(parents=True)
    # Bind immutable per-output source bytes, so future tool extensions do not
    # invalidate old oracle headers or weaken the runner's live-input guards.
    frozen_generator = out/'m2_user_intro_oracle.py'
    frozen_generator.write_bytes(Path(__file__).read_bytes())
    paths[0] = frozen_generator
    records = []
    for frame in frames:
        state = {}
        scene_paths = list(paths)
        for key, (field, fmt) in fields.items():
            p = capture/('f%05d-%s.bin' % (frame, field))
            need(sha(p) == output_hashes[p.name], 'Original capture output hash mismatch: '+p.name)
            state[key] = list(struct.unpack(fmt, p.read_bytes()))
            scene_paths.append(p)
        mixer.verify_configuration(state)
        need(state['K55REGS'][45] == 0x1f, 'Expected original layer enable mask')
        brightness = [state['K38REGS'][11] & 255, state['K38REGS'][12] >> 8, state['K38REGS'][12] & 255]
        need(brightness == [255, 255, 255], 'Scene must stay within unchanged brightness model')
        inputs = {str(p.resolve()): sha(p) for p in scene_paths}
        packed, summaries, owners = tile.render(state['K56REGS'], state['K55REGS'], state['VRAM'], tp.read_bytes())
        width, height = mixer.W, mixer.H
        values = struct.unpack('<'+str(4*width*height)+'H', packed)
        planes = [values[layer*width*height:(layer+1)*width*height] for layer in range(4)]
        colors, stats, objects, draworder, contributors = mixer.render(state, planes, sp.read_bytes(), sprite, rgb)
        need(len(colors) == width*height and all(0 <= c <= 0xffffff for c in colors), 'Full RGB oracle coverage')
        records.append(write_scene(out, frame, capture, mixer, state, inputs, tp, sp, packed, colors, stats, objects, draworder, summaries, owners, brightness, scalar_checks))
    report = dict(passed=True, reviewer='verification_apf', scope=__doc__, frames=frames,
                  immutable_generator_sha256=sha(frozen_generator), records=records,
                  historical_MAME_pixels_consumed=False, user_screenshot_consumed=False,
                  RGB_scalar_crosschecks=scalar_checks, hardware_verified=False)
    (out/'manifest.json').write_text(json.dumps(report, indent=2)+'\n')
    return 0


def write_scene(out, frame, capture, mixer, state, inputs, tp, sp, packed, colors, stats, objects, draworder, summaries, owners, brightness, scalar_checks):
    width, height = mixer.W, mixer.H
    scene = out/('scene-f%05d' % frame)
    scene.mkdir()
    state_path = scene/'state.txt'
    state_path.write_text(mixer.state_text(state, frame))
    pixels = scene/'rgb.bin'
    pixels.write_bytes(struct.pack('<'+str(width*height)+'I', *colors))
    pp = scene/'tile-planes.bin'
    pp.write_bytes(packed)
    image = scene/'oracle.png'
    png(image, colors, width, height)
    header = dict(schema=1, set='mystwarr', title='Mystic Warriors (ver EAA)', frame=frame,
                  capture=str(capture), source_kind='original_capture', mame_commit=mixer.PIN, profile_mystic=True,
                  width=width, height=height, visible_origin=[mixer.X0, mixer.Y0], sprite_offsets=[-48, -24],
                  dtype='u32LE 0x00RRGGBB', order='row-major, x increasing', pixels=width*height,
                  pixels_path=str(pixels), pixels_sha256=sha(pixels), state_path=str(state_path), state_sha256=sha(state_path),
                  tile_planes_path=str(pp), tile_planes_sha256=sha(pp),
                  tile_planes_format='four layer-major u16LE planes, palette11:0,opaque12,category14:13',
                  canonical_tile_ROM=str(tp), canonical_sprite_ROM=str(sp),
                  state_semantics='u16LE captures expressed as hex words; SPRITERAM is internal2048word K47list; VRAM17pages; PALETTE4096words00RR/GGBB',
                  backdrop_mode='Mystic solid K338 background; no GX WRPORT override', constructed_parent=None, constructed_deltas=None,
                  registers={key: state[key] for key in ('K46REGS','K47REGS','K55REGS','K38REGS','K56REGS','K56REGSB')},
                  objects=objects, global_paint_order=draworder, tile_summaries=summaries, page_owners=owners,
                  statistics=stats, constructed_checks={}, unsupported=mixer.LIMITS, inputs_sha256=inputs,
                  hardware_verified=False, game_playable=False)
    hp = scene/'header.json'
    hp.write_text(json.dumps(header, indent=2)+'\n')
    need(all(sha(Path(p)) == digest for p, digest in inputs.items()), 'Oracle inputs changed during generation')
    report = dict(passed=True, reviewer='verification_apf', frame=frame, source_kind='original_capture',
                  scope=__doc__, historical_MAME_pixels_consumed=False, user_screenshot_consumed=False,
                  RGB_scalar_crosschecks=scalar_checks, brightness=brightness, layer_enable=state['K55REGS'][45],
                  inputs_sha256=inputs, inputs_unchanged=True, header_path=str(hp), header_sha256=sha(hp),
                  pixels_sha256=sha(pixels), state_sha256=sha(state_path), tile_planes_sha256=sha(pp), diagnostic_png_sha256=sha(image),
                  statistics=stats, hardware_verified=False)
    print(hp)
    print('RGB', report['pixels_sha256'])
    return report


if __name__ == '__main__':
    raise SystemExit(main())
