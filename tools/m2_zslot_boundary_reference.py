#!/usr/bin/env python3
"""Boundary diagnostic: unmodified original states, candidate Z exclusion; contract may fail."""
import argparse
from collections import defaultdict
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import sys

sys.dont_write_bytecode = True
WORK = Path(__file__).resolve().parents[1]
PROJECT = WORK.parents[1]
MODELS = {
    'm2_user_intro_oracle.py': '8bd42ea93b8b6102105e82e52786fdd720dce1078aadec3a30388224318c9940',
    'm2_mixer_reference.py': 'df2020d6e43dd7d110702a63d1d63a82f220fd5d5ffa8298b08bbbdb55340c5e',
    'm2_tile_reference.py': 'fb260491fc6b95e5c8dcaaf392bc00a20c8ac2d7146a8e89adbb067b38715ef3',
    'm2_sprite_reference.py': '3541fd51952b7e28f6563cf014d902ab120b54a267011e6b5594ff860ead83d9',
    'm2_rgb_reference.py': '0ca0ed4be567f0a54fbbb20226dab579363119535e6975fd1f5949ee6df12ac5',
}
PARENT_GENERATOR_SHA = '4a8e153553172fff583cbbc0102fee34a7843650fd5c27b5647a0180b998c18f'
HISTORIC_SHA = '3e0de72c83b15bbfbde935e1f73df3c77da5067c9851873ecc8009f4ac95e36e'
FIELDS = {'K46REGS': ('k46_regs', '<8B'), 'K47REGS': ('k47_regs', '<16H'),
          'K55REGS': ('k55_regs', '<128B'), 'K38REGS': ('k38_regs', '<32H'),
          'SPRITERAM': ('k47_list', '<2048H'), 'K56REGS': ('k56_regs', '<32H'),
          'K56REGSB': ('k56_regsb', '<4H'), 'VRAM': ('k56_vram', '<69632H'),
          'PALETTE': ('palette', '<4096H')}
NAME_ENTRIES = {'YURI': [0, 1], 'KEIMA': [2, 3], 'BRAD': [4, 5], 'KOJIRO': [6], 'SPYROS': [7]}
TIGHT_CROPS = {'KEIMA': [177, 17, 214, 31], 'YURI': [17, 57, 47, 69],
               'BRAD': [17, 145, 48, 159], 'KOJIRO': [154, 193, 193, 207],
               'SPYROS': [232, 129, 272, 143]}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def zslots(ram):
    """Select globally before callbacks, Y visibility or mode expansion."""
    groups = defaultdict(list)
    for i in range(256):
        if ram[i*8] & 0x8000:
            groups[ram[i*8] & 255].append(i)
    winners = {z: max(entries) for z, entries in groups.items()}
    losers = sorted(i for z, entries in groups.items() for i in entries if i != winners[z])
    return groups, winners, losers


def inside(at, box):
    x, y = at % 288, at // 288
    return box[0] <= x < box[2] and box[1] <= y < box[3]


def packed_record(obj):
    # Model order leaves bits3:2 empty. The actual public list ABI carries the
    # captured shadow condition there; do not compare list_q to model.order.
    return ((obj['priority'] << 24) | (obj['z'] << 16) |
            (obj['object_index'] << 8) | (obj['drawmode'] << 4) |
            (obj['shadow_condition'] << 2) | obj['shadow_table'])


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--historic-source', type=Path, required=True)
    ap.add_argument('--historic-provenance', type=Path, required=True)
    ap.add_argument('--historic-url', required=True)
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = out/'source'
    (source/'tools').mkdir(parents=True)
    report = dict(schema=1, passed=False, reviewer='verification_apf', executor='verification_apf',
                  source_kind='original_capture_zslot_hypothesis', hardware_verified=False,
                  current_MAME_runtime_golden=False, records=[], scope=__doc__)
    try:
        assert sha(WORK/'tools/m2_zslot_reference.py') == PARENT_GENERATOR_SHA
        shutil.copy2(WORK/'tools/m2_zslot_reference.py', source/'tools/m2_zslot_reference.py')
        for name, digest in MODELS.items():
            assert sha(WORK/'tools'/name) == digest, name+' changed'
            shutil.copy2(WORK/'tools'/name, source/'tools'/name)
        shutil.copy2(Path(__file__), source/'tools'/Path(__file__).name)
        assert sha(args.historic_source) == HISTORIC_SHA
        frozen_historic = source/args.historic_source.name
        shutil.copy2(args.historic_source, frozen_historic)
        provenance = json.loads(args.historic_provenance.read_text())
        assert provenance['sha256'] == HISTORIC_SHA and provenance['immutable_url'] == args.historic_url
        shutil.copy2(args.historic_provenance, source/'historic-provenance.json')
        # Keep the primary-source audit stable even when later root docs change.
        audit = provenance['sealed_research_audit']
        for key in ('doc', 'evidence'):
            p = PROJECT/audit[key]
            assert sha(p) == audit[key+'_sha256']
            shutil.copy2(p, source/p.name)
        policy = dict(name='Mystic diagnostic ACTIVE global Z-slot exclusion; high RAM wins',
                      active_only=True, global_before_Y_or_priority=True, highest_RAM_index_wins=True,
                      applies_to='Mystic diagnostic candidate only; Gaia unchanged',
                      historical_source=dict(path=str(frozen_historic), sha256=HISTORIC_SHA,
                                             url=args.historic_url, span='K053247_sprites_draw, lines3569..3637'),
                      historical_provenance=dict(path=str(source/'historic-provenance.json'),
                                                 sha256=sha(source/'historic-provenance.json')),
                      source_limit='MAME0.63 actual bucket loop included inactive entries (active guard commented). ACTIVE-only is a declared candidate choice, not an identical historical rule.',
                      PCB_source='https://www.youtube.com/watch?v=PdEG0cq_qU4', PCB_ROM_revision_known=False,
                      inference='Historical exclusion-sort shape plus PCB-labelled truck without names and original eight exact Z collisions. Not proven K055673 silicon behaviour; current MAME0.220/0.264/0.289 retain the names.',
                      ROM_RAM_register_palette_mutations=False, current_MAME_golden=False)
        (source/'policy.json').write_text(json.dumps(policy, indent=2)+'\n')
        helper = load('frozen_intro', source/'tools/m2_user_intro_oracle.py')
        mixer = load('frozen_mixer', source/'tools/m2_mixer_reference.py')
        tile, sprite, rgb = [mixer.load_module(n) for n in mixer.MODULE_HASHES]
        tp, sp = [PROJECT/'private/mystwarr-regions'/n for n in ('k056832.bin', 'k055673.bin')]
        assert sha(tp) == tile.ROM_SHA and sha(sp) == sprite.ROM_SHA
        tr, sr = tp.read_bytes(), sp.read_bytes()
        vector = PROJECT/'private/m2-rgb-oracle/vectors.txt'
        assert sha(vector) == 'c9a2458fc7dad0e2edd49f69bbc85635f5acda3cf55bdff016ecf96b6c977efd'
        checks = 0
        for line in vector.read_text().splitlines():
            s, d, level, is_tile, expected = [int(x, 16) for x in line.split()]
            assert rgb.evaluate(s, d, level, is_tile) == expected
            checks += 1
        assert checks == 6726
        common = {str(p): sha(p) for p in source.rglob('*') if p.is_file()}
        common.update({str(p):sha(p) for p in (tp, sp, vector)})
        # Bind the existing models' normative sources without changing them.
        normative = dict(sprite.SOURCES)
        normative.update({'ref/mame/'+n:h for n,h in tile.SOURCES.items()})
        normative.update(rgb.SOURCES)
        for rel, digest in normative.items():
            p = PROJECT/rel
            assert sha(p) == digest, rel
            common[str(p)] = digest
        for frame, capname in [(3999, 'zslot-transition01'), (4009, 'zslot-transition01'), (4010, 'zslot-transition01')]:
            capture = WORK/'private/mystic-capture'/capname
            rawdir = source/f'original-f{frame:05d}'
            rawdir.mkdir()
            original_hashes = {Path(l.split()[1]).name:l.split()[0] for l in (capture/'outputs.sha256').read_text().splitlines() if l.strip()}
            inputs = dict(common)
            for name in ('outputs.sha256', 'inputs.sha256', 'parameters.txt', 'version.txt'):
                shutil.copy2(capture/name, rawdir/name)
                inputs[str(rawdir/name)] = sha(rawdir/name)
            state = {}
            for key, (suffix, fmt) in FIELDS.items():
                p = capture/f'f{frame:05d}-{suffix}.bin'
                assert sha(p) == original_hashes[p.name]
                q = rawdir/p.name
                shutil.copy2(p, q)
                state[key] = list(struct.unpack(fmt, q.read_bytes()))
                inputs[str(q)] = sha(q)
            mixer.verify_configuration(state)
            original_state_text = mixer.state_text(state, frame)
            brightness = [state['K38REGS'][11]&255, state['K38REGS'][12]>>8, state['K38REGS'][12]&255]
            assert brightness == [255]*3 and state['K55REGS'][45] == 31
            packed, summaries, owners = tile.render(state['K56REGS'], state['K55REGS'], state['VRAM'], tr)
            values = struct.unpack('<258048H', packed)
            planes = [values[i*64512:(i+1)*64512] for i in range(4)]
            baseline, _, original_objects, _, _ = mixer.render(state, planes, sr, sprite, rgb)
            groups, winners, losers = zslots(state['SPRITERAM'])
            assert losers == [], 'Observed original boundary states have no Z collisions'
            all_buckets = {state['SPRITERAM'][i*8]&255:i for i in range(256)}
            all_entry_active_winners = sorted(i for i in all_buckets.values() if state['SPRITERAM'][i*8]&0x8000)
            assert all_entry_active_winners == sorted(winners.values())
            colors, stats, objects, order, _ = mixer.render(state, planes, sr, sprite, rgb, omit=losers)
            # Assert removal changes neither surviving object attributes nor order.
            assert objects == [o for o in original_objects if o['object_index'] not in losers]
            record = helper.write_scene(out, frame, capture, mixer, state, inputs, tp, sp,
                                        packed, colors, stats, objects, order, summaries, owners, brightness, checks)
            scene = out/f'scene-f{frame:05d}'
            assert (scene/'state.txt').read_text() == original_state_text
            (scene/'baseline-rgb.bin').write_bytes(struct.pack('<64512I', *baseline))
            helper.png(scene/'baseline.png', baseline, 288, 224)
            changed = {i for i,(before,after) in enumerate(zip(baseline,colors)) if before != after}
            footprints = {}
            cache = {}
            for name, entries in NAME_ENTRIES.items():
                coords = {at for o in original_objects if o['object_index'] in entries
                          for at, pen in mixer.sprite_pixels(state, o, sr, sprite, cache) if pen}
                if coords:
                    footprints[name] = [min(i%288 for i in coords),min(i//288 for i in coords),
                                        max(i%288 for i in coords)+1,max(i//288 for i in coords)+1]
            diff = dict(changed_pixels=len(changed),
                        outside_previous_tight_name_crops=sum(not any(inside(i,b) for b in TIGHT_CROPS.values()) for i in changed),
                        previous_tight_name_crops=TIGHT_CROPS,
                        full_name_sprite_boxes=footprints,
                        outside_full_name_sprite_boxes=sum(not any(inside(i,b) for b in footprints.values()) for i in changed))
            if frame in (3999, 4009, 4010):

                assert not changed
            else:
                assert changed and diff['outside_full_name_sprite_boxes'] == 0
            hp = scene/'header.json'
            h = json.loads(hp.read_text())
            records = [dict(packed32_hex=f'{packed_record(o):08x}', **o) for o in objects]
            transition_contract = dict(requirement='Names absent once portraits disappear; supported partial samples already disprove compliance', last_supported_presentation_sample=3999, last_portrait_RGB=4004, first_no_portrait_RGB=4005, first_successor_map_state=4001, original_RGB_first_new_map=4002, exact_consecutive_boundary_rendered=False, API_phase='State and screen pixels are sampled in register_frame; diagnostic crosschecks below assess phase, not a bus edge', candidate_names_in_object_list=sorted({o['object_index'] for o in objects if o['object_index'] < 8}), successor_names_absent=not any(o['object_index'] < 8 for o in objects), passed=(frame == 3999))
            diagnostics = {}
            for sample in (frame-1, frame, frame+1):
                px = capture/f'f{sample:05d}-pixels-current.bin'
                original = struct.unpack('<64512I', px.read_bytes())
                diagnostics[str(sample)] = dict(sha256=sha(px), RGB_mismatches=sum((a&0xffffff) != b for a,b in zip(original, baseline)))
            h.update(transition_contract=transition_contract, original_RGB_phase_diagnostic=diagnostics, source_kind='original_capture_zslot_hypothesis', reviewer='verification_apf',
                     policy=policy, normative_status='Diagnostic inferred policy; not current-MAME runtime golden or verified silicon',
                     base_model_mame_commit=h['mame_commit'],
                     mame_commit_contract_note='Base immutable models only; unique-Z selection is an additional inferred policy.',
                     original_state_payload_unchanged=True, omitted_original_object_indices=losers,
                     expected_active_entries_before=sum(map(len,groups.values())), expected_active_entries_after=len(winners),
                     selected_zslot_winners={str(z):i for z,i in sorted(winners.items())},
                     all_entry_and_ACTIVE_only_selection_agree_for_this_original_state=True,
                     expected_object_list_records=records,
                     expected_object_list_ABI='priority[31:24],Z[23:16],entry[15:8],mode[7:4],condition[3:2],table[1:0]; model order excludes condition bits',
                     baseline_rgb_sha256=sha(scene/'baseline-rgb.bin'), RGB_policy_difference=diff,
                     historical_MAME_pixels_consumed=False, historical_MAME_pixels_read_for_phase_only=True, user_screenshot_consumed=False)
            hp.write_text(json.dumps(h, indent=2)+'\n')
            record.update(source_kind=h['source_kind'], scope=__doc__, policy=policy,
                          header_sha256=sha(hp), transition_contract=transition_contract, original_RGB_phase_diagnostic=diagnostics, original_state_payload_unchanged=True,
                          omitted_original_object_indices=losers, active_before=h['expected_active_entries_before'],
                          active_after=h['expected_active_entries_after'], list_records_before=len(original_objects),
                          list_records_after=len(objects), RGB_policy_difference=diff)
            report['records'].append(record)
        assert all(sha(Path(p)) == digest for rec in report['records'] for p,digest in rec['inputs_sha256'].items())
        report.update(passed=False, generation_passed=True, transition_contract_passed=False, contract_failure='All eight names survive candidate selection in supported-brightness successor states4009 and4010; no Z collisions until4011. First map state4001 excluded from RGB model by non255 brightness.', policy=policy, inputs_unchanged=True, new_native_DUT_executions=0,
                      current_MAME_runtime_golden=False, historical_MAME_pixels_consumed=False,
                      outputs_sha256={str(p.relative_to(out)):sha(p) for p in out.rglob('*') if p.is_file()})
    except Exception as exc:
        report['error'] = str(exc)
        raise
    finally:
        (out/'manifest.json').write_text(json.dumps(report, indent=2)+'\n')
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
