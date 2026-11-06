#!/usr/bin/env python3
"""Convert RGB8 noninterlaced PNG into the SDK's 36x36 Pocket author icon.
Box averaging, luminance threshold 48; 16-bit little-endian brightness,
rotated 90 degrees counterclockwise. No external image library required.
"""
import argparse, struct, zlib
from pathlib import Path
SIGNATURE=b'\x89PNG\r\n\x1a\n'
def chunk(kind,data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
def convert(source):
    body=source.read_bytes(); assert body.startswith(SIGNATURE)
    pos=8; encoded=bytearray(); header=None
    while pos<len(body):
        n=struct.unpack_from('>I',body,pos)[0];kind=body[pos+4:pos+8];data=body[pos+8:pos+8+n]
        assert zlib.crc32(kind+data)==struct.unpack_from('>I',body,pos+8+n)[0]
        pos+=n+12
        if kind==b'IHDR':header=data
        elif kind==b'IDAT':encoded.extend(data)
        elif kind==b'IEND':break
    assert pos==len(body) and header
    w,h,depth,color,compression,filtering,interlace=struct.unpack('>IIBBBBB',header)
    assert depth==8 and color==2 and not (compression or filtering or interlace)
    assert 36<=w<=4096 and 36<=h<=4096
    raw=zlib.decompress(encoded); stride=w*3; assert len(raw)==h*(stride+1)
    rows=[]; prev=bytes(stride)
    for y in range(h):
        f=raw[y*(stride+1)]; row=bytearray(raw[y*(stride+1)+1:(y+1)*(stride+1)])
        assert f<=4
        for x in range(stride):
            a=row[x-3] if x>=3 else 0; b=prev[x]; c=prev[x-3] if x>=3 else 0
            if f==0:q=0
            elif f==1:q=a
            elif f==2:q=b
            elif f==3:q=(a+b)//2
            else:
                p=a+b-c;pa,pb,pc=abs(p-a),abs(p-b),abs(p-c)
                q=a if pa<=pb and pa<=pc else b if pb<=pc else c
            row[x]=(row[x]+q)&255
        rows.append(row);prev=row
    upright=[]
    for y in range(36):
        out=[]
        for x in range(36):
            values=[(299*rows[yy][3*xx]+587*rows[yy][3*xx+1]+114*rows[yy][3*xx+2])//1000
                    for yy in range(y*h//36,(y+1)*h//36)
                    for xx in range(x*w//36,(x+1)*w//36)]
            out.append(255 if sum(values)>=48*len(values) else 0)
        upright.append(out)
    icon=b''.join(struct.pack('<H',upright[x][35-y]<<8) for y in range(36) for x in range(36))
    preview=SIGNATURE+chunk(b'IHDR',struct.pack('>IIBBBBB',36,36,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(b'\0'+bytes(v for p in row for v in (p,p,p)) for row in upright),9))+chunk(b'IEND',b'')
    assert len(icon)==2592 and set(icon[0::2])=={0}
    # Recover upright orientation through the inverse storage rotation.
    assert all(struct.unpack_from('<H',icon,2*((35-x)*36+y))[0]>>8==upright[y][x] for y in range(36) for x in range(36))
    return icon,preview
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('source',type=Path);ap.add_argument('icon',type=Path);ap.add_argument('--preview',type=Path);a=ap.parse_args()
    icon,preview=convert(a.source)
    with a.icon.open('xb') as f:f.write(icon)
    if a.preview:
        with a.preview.open('xb') as f:f.write(preview)
