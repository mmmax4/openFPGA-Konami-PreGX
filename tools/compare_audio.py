#!/usr/bin/env python3
"""Compare the bench's audio (sim/run_system.sh AUDIO=1) with MAME's recording.

Both are 48 kHz stereo 16-bit WAVs from reset. The two machines drift apart
in absolute time (the RTL's 68000 pacing is approximate), so the comparison
is envelope-based: the first non-silent instant of each file is aligned, then
the RMS of every 50 ms window is compared for as long as both files last.
Prints the alignment, per-channel level difference in dB and the envelope
correlation; -v prints every window.

usage: compare_audio.py <rtl.wav> <mame.wav> [-v]
"""
import sys, struct, math


def read_wav(path):
    d = open(path, 'rb').read()
    i, fmt, data = 12, None, None
    while i < len(d):
        cid, sz = d[i:i + 4], struct.unpack('<I', d[i + 4:i + 8])[0]
        if cid == b'fmt ':
            fmt = struct.unpack('<HHIIHH', d[i + 8:i + 24])
        elif cid == b'data':
            data = d[i + 8:i + 8 + sz]
            break
        i += 8 + sz + (sz & 1)
    ch, rate = fmt[1], fmt[2]
    n = len(data) // 2
    s = struct.unpack('<%dh' % n, data[:n * 2])
    return rate, s[0::ch], s[1::ch] if ch > 1 else s[0::ch]


def first_sound(l, r, thr=64):
    for i in range(len(l)):
        if abs(l[i]) > thr or abs(r[i]) > thr:
            return i
    return None


def envelope(x, win):
    out = []
    for k in range(0, len(x) - win + 1, win):
        seg = x[k:k + win]
        out.append(math.sqrt(sum(v * v for v in seg) / win))
    return out


def db(a, b):
    return 20 * math.log10((a + 1e-9) / (b + 1e-9))


def corr(a, b):
    n = min(len(a), len(b))
    a, b = a[:n], b[:n]
    ma, mb = sum(a) / n, sum(b) / n
    num = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    den = math.sqrt(sum((x - ma) ** 2 for x in a) * sum((y - mb) ** 2 for y in b)) + 1e-9
    return num / den


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    verbose = '-v' in sys.argv
    rate, rl, rr = read_wav(args[0])
    _, ml, mr = read_wav(args[1])
    a, b = first_sound(rl, rr), first_sound(ml, mr)
    print(f'first sound: rtl {a / rate if a is not None else None:.3f}s  mame {b / rate:.3f}s'
          if a is not None else f'first sound: rtl NONE  mame {b / rate:.3f}s')
    if a is None:
        sys.exit(1)
    win = rate // 20
    el, er = envelope(rl[a:], win), envelope(rr[a:], win)
    fl, fr = envelope(ml[b:], win), envelope(mr[b:], win)
    n = min(len(el), len(fl))
    if n == 0:
        sys.exit('no overlap after alignment')
    el, er, fl, fr = el[:n], er[:n], fl[:n], fr[:n]
    mean = lambda x: sum(x) / len(x)
    print(f'{n} windows of 50 ms compared ({n / 20:.1f}s)')
    print(f'level rtl-mame: L {db(mean(el), mean(fl)):+.1f} dB  R {db(mean(er), mean(fr)):+.1f} dB')
    print(f'envelope correlation: L {corr(el, fl):.3f}  R {corr(er, fr):.3f}')
    if verbose:
        for k in range(n):
            print(f'{k * 0.05:6.2f}s  rtl L {el[k]:7.0f} R {er[k]:7.0f}   mame L {fl[k]:7.0f} R {fr[k]:7.0f}')


if __name__ == '__main__':
    main()
