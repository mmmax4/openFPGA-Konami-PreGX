#!/usr/bin/env python3
"""Prove a black brightness endpoint using unchanged original Mystic inputs.

This is a source endpoint proof, not a replacement full mixer model or a
historical MAME/Pocket golden. Existing independent models stay unchanged.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import sys
import traceback

sys.dont_write_bytecode = True
MODEL_SHA = 'df2020d6e43dd7d110702a63d1d63a82f220fd5d5ffa8298b08bbbdb55340c5e'
HELPER_SHA = '8bd42ea93b8b6102105e82e52786fdd720dce1078aadec3a30388224318c9940'
BRI_SHA = '102fa08707a46265695ca924bbdc112ca8ccf3e95493b58439272014b21fdbf6'
BASELINE_3900_SHA = 'e4348eda506beaebaf96279018e89b6806cc72cf38eb606933dfc94e4001d739'
SNOW_HEADER_SHA = 'f1e99dbeb9fa826a09caebd102418a32fb17f5efa5ba8ec9f0bef5167769b30f'
FIELDS = {'K46REGS': ('k46_regs', '<8B'), 'K47REGS': ('k47_regs', '<16H'),
          'K55REGS': ('k55_regs', '<128B'), 'K38REGS': ('k38_regs', '<32H'),
          'SPRITERAM': ('k47_list', '<2048H'), 'K56REGS': ('k56_regs', '<32H'),
          'K56REGSB': ('k56_regsb', '<4H'), 'VRAM': ('k56_vram', '<69632H'),
          'PALETTE': ('palette', '<4096H')}


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def need(ok, message):
    if not ok:
        raise ValueError(message)


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def state(capture, frame):
    checksums = {Path(line.split()[1]).name: line.split()[0]
                 for line in (capture/'outputs.sha256').read_text().splitlines() if line.strip()}
    result, paths = {}, [capture/name for name in ['outputs.sha256', 'inputs.sha256', 'parameters.txt', 'version.txt']]
    for key, (suffix, fmt) in FIELDS.items():
        path = capture/('f%05d-%s.bin' % (frame, suffix))
        need(sha(path) == checksums[path.name], 'Original capture changed: '+path.name)
        result[key] = list(struct.unpack(fmt, path.read_bytes()))
        paths.append(path)
    return result, paths


def factors(st):
    r = st['K38REGS']
    return [r[11] & 255, r[12] >> 8, r[12] & 255]


def apply_bri(component, factor):
    return component if factor == 255 else (component*factor) >> 8


def factor_for(selector, values):
    return values[selector-1] if selector else 255


def all_black_color(color, factor):
    return all(apply_bri((color >> shift) & 255, factor) == 0 for shift in (16, 8, 0))


def prove_black(st, packed, sprite_rom, mixer, sprite):
    k55, k38 = st['K55REGS'], st['K38REGS']
    need(not k38[15] & 2, 'MIXPRI semantics are outside endpoint proof')
    need(k55[45] == 31 and k38[15] & 1, 'Original complete Mystic layer enable required')
    backdrop = ((k38[0] & 255) << 16) | k38[1]
    need(backdrop == 0, 'Backdrop must already be black')
    palette = mixer.palette_rgb(st)
    values = factors(st)
    planes = struct.unpack('<%dH' % (4*mixer.W*mixer.H), packed)
    layers = []
    for layer in range(4):
        selector = (k55[42] >> (2*layer)) & 3
        factor = factor_for(selector, values)
        opaque, before_nonzero, after_nonzero = 0, 0, 0
        start = layer*mixer.W*mixer.H
        for value in planes[start:start+mixer.W*mixer.H]:
            if not value & 4096:
                continue
            index = value & 4095
            need(index < len(palette), 'Original tile palette index out of range')
            color = palette[index]
            opaque += 1
            before_nonzero += color != 0
            after_nonzero += not all_black_color(color, factor)
        need(after_nonzero == 0, 'A visible tile contribution is not provably black')
        layers.append(dict(layer=layer, selector=selector, factor=factor, opaque_pixels=opaque,
                           nonzero_palette_before_brightness=before_nonzero,
                           nonzero_contributions_after_brightness=after_nonzero))
    active = [off for off in range(0, 2048, 8) if st['SPRITERAM'][off] & 0x8000]
    need(active, 'Nonvacuous original active sprites required')
    need(all(((st['SPRITERAM'][off+6] >> 10) & 3) == 0 for off in active),
         'Active shadow sprite prevents this sufficient endpoint proof')
    obj_selector = (k55[43] & 3) if k55[44] & 1 else 0
    obj_factor = factor_for(obj_selector, values)
    objects = sprite.objects(st)
    need(len(objects) == len(active) and all(o['drawmode'] < 4 for o in objects),
         'Unexpected shadow/additional object contribution')
    cache, visible, before_nonzero = {}, 0, 0
    for obj in objects:
        for _, pen in mixer.sprite_pixels(st, obj, sprite_rom, sprite, cache):
            if pen == 0 or (obj['drawmode'] & 3 and pen >= 31):
                continue
            color = palette[obj['group']*32+pen]
            visible += 1
            before_nonzero += color != 0
            need(all_black_color(color, obj_factor), 'A visible sprite contribution is not black')
    need(visible > 0 and before_nonzero > 0, 'Nonvacuous decoded original sprite pixels required')
    need(sum(p['nonzero_palette_before_brightness'] for p in layers) > 0,
         'Nonvacuous decoded original tile pixels required')
    return dict(reference_kind='brightness_endpoint_proof', backdrop=backdrop, brightness_factors=values,
                tiles=layers, object_selector=obj_selector, object_factor=obj_factor,
                active_objects=len(active), shadow_objects=0, decoded_visible_sprite_contributions=visible,
                nonzero_sprite_palette_before_brightness=before_nonzero,
                nonzero_sprite_contributions_after_brightness=0,
                ordering_independent=True,
                sufficiency='Every possible visible source contribution is black; transparent pens add nothing; no active shadow; alpha/addition of black over black remains black.'), objects


def run(work, out, frame):
    root = work.parents[1]
    need(4000 <= frame <= 4008, 'Endpoint frame must be an original transition capture 4000..4008')
    need(not out.exists(), 'Preserve previous output; choose a fresh directory')
    model_path, helper_path = work/'tools/m2_mixer_reference.py', work/'tools/m2_user_intro_oracle.py'
    need(sha(model_path) == MODEL_SHA and sha(helper_path) == HELPER_SHA, 'Immutable model/helper changed')
    mixer, helper = module(model_path, 'brightness_mixer'), module(helper_path, 'brightness_writer')
    tile, sprite, rgb = [mixer.load_module(name) for name in mixer.MODULE_HASHES]
    normative = root/'private/reference-mister/ninja-brightness-5996b599/mystwarr_k055555.v'
    need(sha(normative) == BRI_SHA, 'Pinned brightness primary source changed')
    sources = dict(sprite.SOURCES)
    sources.update({'ref/mame/'+name: digest for name, digest in tile.SOURCES.items()})
    sources.update({'private/mame0220/current_drawgfx.h': rgb.SOURCES['private/mame0220/current_drawgfx.h'],
                    'private/mame0220/current_dipalette.cpp': '58343b1dc046faf0d3d28ec0b760ea0850bf74a28a7044bff2dc4ef4d923d248'})
    common = [Path(sys.executable).resolve(), model_path, helper_path, normative, normative.parent/'provenance.json',
              *(work/'tools'/name for name in mixer.MODULE_HASHES)]
    for rel, digest in sources.items():
        need(sha(root/rel) == digest, 'Pinned original model source changed: '+rel)
        common.append(root/rel)
    tile_path, sprite_path = root/'private/mystwarr-regions/k056832.bin', root/'private/mystwarr-regions/k055673.bin'
    need(sha(tile_path) == tile.ROM_SHA and sha(sprite_path) == sprite.ROM_SHA, 'Original graphics identity')
    common.extend([tile_path, sprite_path])
    vector = root/'private/m2-rgb-oracle/vectors.txt'
    need(sha(vector) == 'c9a2458fc7dad0e2edd49f69bbc85635f5acda3cf55bdff016ecf96b6c977efd', 'Frozen RGB vectors changed')
    for line in vector.read_text().splitlines():
        src, dst, level, is_tile, expected = [int(v, 16) for v in line.split()]
        need(rgb.evaluate(src, dst, level, is_tile) == expected, 'Original RGB scalar crosscheck')
    scalar_checks = len(vector.read_text().splitlines())
    need(scalar_checks == 6726, 'RGB vector count')
    common.append(vector)
    for c in range(256):
        need(apply_bri(c, 0) == 0 and apply_bri(c, 255) == c, 'Brightness endpoint identity')
    capture = work/'private/mystic-capture/zslot-transition01'
    st, paths = state(capture, frame)
    original_state = json.dumps(st, sort_keys=True)
    packed, summaries, owners = tile.render(st['K56REGS'], st['K55REGS'], st['VRAM'], tile_path.read_bytes())
    proof, objects = prove_black(st, packed, sprite_path.read_bytes(), mixer, sprite)
    need(json.dumps(st, sort_keys=True) == original_state, 'Original endpoint state mutated')

    # Only create a consumable fixture after every sufficient condition passes.
    out.mkdir(parents=True)
    frozen = out/'source'; frozen.mkdir()
    generator = frozen/'m2_brightness_reference.py'
    shutil.copyfile(Path(__file__).resolve(), generator)
    common.append(generator)
    proof_path = out/'endpoint-proof.json'
    proof_path.write_text(json.dumps(proof, indent=2)+'\n')
    inputs = {str(p.resolve()): sha(p) for p in common+paths+[proof_path]}
    stats = {'endpoint_proof': proof, 'counts': {}, 'max_contributing_alpha_objects': 0}
    black = helper.write_scene(out, frame, capture, mixer, st, inputs, tile_path, sprite_path,
                               packed, [0]*(mixer.W*mixer.H), stats, objects, [], summaries, owners,
                               factors(st), scalar_checks)
    hp = Path(black['header_path']); header = json.loads(hp.read_text())
    header.update(reference_kind='brightness_endpoint_proof', reference_normative_source=str(normative),
                  reference_normative_sha256=BRI_SHA, endpoint_proof_path=str(proof_path),
                  endpoint_proof_sha256=sha(proof_path),
                  reference_scope='Mathematical all-black endpoint from original data and pinned brightness source; no full non255 mixer model or historical bitmap golden.',
                  source_kind_semantics='original_capture describes unchanged RAM, ROM and registers, not a claim that the RGB came from MAME or Pocket.',
                  unsupported=['General non-endpoint brightness mixing', 'Active shadow sprites',
                               'Live midframe register/palette writes', 'Full-game timing and physical Pocket behavior'])
    hp.write_text(json.dumps(header, indent=2)+'\n')
    black.update(reviewer='research_rom_exit', reference_kind='brightness_endpoint_proof',
                 scope=header['reference_scope'], header_sha256=sha(hp), full_mixer_render_invoked=False)
    need(Path(header['state_path']).read_text() == mixer.state_text(st, frame), 'Endpoint state serialization changed')
    need(Path(header['tile_planes_path']).read_bytes() == packed, 'Original endpoint tile planes changed')
    need(Path(header['pixels_path']).read_bytes() == b'\0'*(mixer.W*mixer.H*4), 'Black endpoint payload')

    control_capture = work/'private/mystic-capture/user-attract04'
    control, control_paths = state(control_capture, 3900)
    mixer.verify_configuration(control)
    need(factors(control) == [255, 255, 255], 'Original3900 identity endpoint required')
    control_before = json.dumps(control, sort_keys=True)
    cp, cs, co = tile.render(control['K56REGS'], control['K55REGS'], control['VRAM'], tile_path.read_bytes())
    values = struct.unpack('<%dH' % (4*mixer.W*mixer.H), cp)
    planes = [values[layer*mixer.W*mixer.H:(layer+1)*mixer.W*mixer.H] for layer in range(4)]
    colors, cstats, objs, order, _ = mixer.render(control, planes, sprite_path.read_bytes(), sprite, rgb)
    need(json.dumps(control, sort_keys=True) == control_before, 'Original3900 state mutated')
    baseline = work/'private/mystic-zslot-oracle/zslot01/scene-f03900/baseline-rgb.bin'
    need(sha(baseline) == BASELINE_3900_SHA, 'Historical ordinary baseline changed')
    expected = struct.pack('<%dI' % (mixer.W*mixer.H), *colors)
    need(expected == baseline.read_bytes(), '3900 differs from unchanged ordinary baseline')
    ci = {str(p.resolve()): sha(p) for p in common+control_paths+[baseline]}
    ordinary = helper.write_scene(out, 3900, control_capture, mixer, control, ci, tile_path, sprite_path,
                                  cp, colors, cstats, objs, order, cs, co, factors(control), scalar_checks)
    ordinary.update(reviewer='research_rom_exit', reused_baseline_rgb_sha256=sha(baseline), baseline_byte_identical=True)

    snow_path = work/'private/mystic-user-intro-oracle/snow04/scene-f04476/header.json'
    need(sha(snow_path) == SNOW_HEADER_SHA, 'Existing4476 original header changed')
    snow = json.loads(snow_path.read_text())
    need(snow['frame'] == 4476 and snow['source_kind'] == 'original_capture', '4476 original identity')
    snow_state, snow_paths = state(Path(snow['capture']), 4476)
    mixer.verify_configuration(snow_state)
    need(factors(snow_state) == [255, 255, 255], 'Original4476 identity endpoint required')
    for key in ['state', 'pixels', 'tile_planes']:
        need(sha(snow[key+'_path']) == snow[key+'_sha256'], 'Existing4476 payload changed')
    need(Path(snow['state_path']).read_text() == mixer.state_text(snow_state, 4476), '4476 unchanged original state')
    for p, digest in snow['inputs_sha256'].items():
        need(sha(p) == digest, 'Existing4476 original input changed: '+p)
    reused = dict(frame=4476, header_path=str(snow_path), header_sha256=sha(snow_path),
                  pixels_sha256=snow['pixels_sha256'], reused_without_render=True, brightness=factors(snow_state))
    all_inputs = dict(inputs); all_inputs.update(ci)
    all_inputs.update({str(p.resolve()): sha(p) for p in snow_paths+[snow_path]})
    need(all(sha(p) == digest for p, digest in all_inputs.items()), 'Inputs changed during endpoint generation')
    return dict(schema=1, passed=True, complete=True, reviewer='research_rom_exit',
                scope=__doc__, reference_kind='brightness_endpoint_proof', records=[black, ordinary, reused],
                inputs_sha256=all_inputs, inputs_unchanged=True, original_state_or_rom_patched=False,
                immutable_model_or_helper_modified=False, brightness_endpoint_scalar_checks=512,
                RGB_scalar_crosschecks=scalar_checks, historical_MAME_pixels_consumed=False,
                user_or_Pocket_pixels_consumed=False, native_consumer_executed=False,
                generator_sha256=sha(generator), outputs_sha256={str(p.relative_to(out)): sha(p)
                    for p in out.rglob('*') if p.is_file() and p.name != 'manifest.json'})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project-root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output', type=Path)
    parser.add_argument('--frame', type=int, default=4000)
    args = parser.parse_args(); work = args.project_root.resolve()
    out = (args.output or work/'private/mystic-brightness-oracle/brightness01').resolve()
    started = datetime.now(timezone.utc).isoformat()
    try:
        result = run(work, out, args.frame)
        result.update(started_utc=started, finished_utc=datetime.now(timezone.utc).isoformat(),
                      command=[sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]],
                      python=sys.version, native_exit=0, child_reaped=True)
        (out/'native.exit').write_text('0\n')
        result['outputs_sha256']['native.exit'] = sha(out/'native.exit')
        (out/'manifest.json').write_text(json.dumps(result, indent=2)+'\n')
        print(json.dumps({'complete':True, 'headers':[r['header_path'] for r in result['records']],
                          'endpoint_proof':str(out/'endpoint-proof.json'), 'native_consumer_executed':False}))
        return 0
    except Exception as error:
        if out.exists() and not (out/'manifest.json').exists():
            (out/'native.exit').write_text('1\n')
            (out/'failure.txt').write_text(traceback.format_exc())
            (out/'manifest.json').write_text(json.dumps(dict(complete=False, passed=False,
                native_exit=1, child_reaped=True, started_utc=started,
                finished_utc=datetime.now(timezone.utc).isoformat(), error=str(error)), indent=2)+'\n')
        raise


if __name__ == '__main__':
    raise SystemExit(main())
