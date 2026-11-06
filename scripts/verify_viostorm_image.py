#!/usr/bin/env python3
"""Recover every original Violent Storm EAC member from a transport image.
Independent of the builder's region construction: uses direct inverse lane
slices, frozen original CRC/SHA1 declarations and byte comparisons to the ZIP.
"""
import argparse, hashlib, json, re, zipfile, zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
EXPECTED='07cdcf2f1b23c16ef1e440e59331974e406be9847204e4e3ad1107a625b7088c'
def verify(image, rom_zip, driver):
    src=driver.read_bytes()
    assert hashlib.sha256(src).hexdigest()=='f6c1ba57e7522803c48b3437e51744ecae3183d4be725d7a7b93c20e2d49199a'
    section=src.decode().split('ROM_START( viostorm )',1)[1].split('ROM_END',1)[0]
    declarations=re.findall(r'ROM_LOAD\w*\(\s*"([^"]+)"\s*,\s*0x[\da-f]+\s*,\s*(0x[\da-f]+)\s*,\s*CRC\(([\da-f]+)\) SHA1\(([\da-f]+)\)',section)
    data=image.read_bytes(); assert len(data)==0x1240080
    # Recover native source byte order without constructing any MAME regions.
    originals={
      '168eac01.15h':data[1:0x100000:2], '168eac02.15f':data[0:0x100000:2],
      '168a05.7c':data[0x200000:0x220000],
      '168a06.1c':data[0x640000:0x840000], '168a07.1e':data[0x840000:0xa40000],
      'viostorm.nv':data[0x1240000:]}
    for name,lane in [('168a09.1h',0),('168a08.1k',2)]:
        out=bytearray(0x200000)
        out[0::2]=data[0x240000+lane+1:0x640000:4]
        out[1::2]=data[0x240000+lane:0x640000:4]
        originals[name]=bytes(out)
    for name,lane in [('168a10.22k',0),('168a11.19k',2),('168a12.20k',4),('168a13.17k',6)]:
        out=bytearray(0x200000)
        out[0::2]=data[0xa40000+lane:0x1240000:8]
        out[1::2]=data[0xa40000+lane+1:0x1240000:8]
        originals[name]=bytes(out)
    assert not any(data[0x100000:0x200000]),'main CPU unpopulated space changed'
    assert data[0x200000:0x220000]==data[0x220000:0x240000],'sound reload changed'
    assert len(declarations)==12 and set(originals)=={e[0] for e in declarations}
    checks=[]
    with zipfile.ZipFile(rom_zip) as z:
        assert len(z.namelist())==12 and set(z.namelist())==set(originals)
        for name,size,crc,s1 in declarations:
            recovered=originals[name]; original=z.read(name)
            assert len(recovered)==int(size,16) and recovered==original,name
            assert f'{zlib.crc32(recovered):08x}'==crc and hashlib.sha1(recovered).hexdigest()==s1,name
            checks.append({'name':name,'bytes':len(recovered),'sha256':hashlib.sha256(recovered).hexdigest(),'original_bytes_equal':True})
    digest=hashlib.sha256(data).hexdigest();assert digest==EXPECTED,'qualified transport digest mismatch'
    return {'status':'passed','reviewer':'standalone inverse verifier','image_sha256':digest,'members':checks,'padding_zero':True,'sound_reload_equal':True,'rom_or_eeprom_patched':False}
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--image',type=Path,required=True);ap.add_argument('--rom-zip',type=Path,required=True)
    ap.add_argument('--driver',type=Path,default=ROOT/'ref/mame0289/mystwarr.cpp')
    ap.add_argument('--output',type=Path);args=ap.parse_args()
    result=verify(args.image,args.rom_zip,args.driver)
    if args.output:
        with args.output.open('x') as f:f.write(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'status':result['status'],'members_verified':len(result['members']),'image_sha256':result['image_sha256']}))
