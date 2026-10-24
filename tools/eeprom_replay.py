#!/usr/bin/env python3
"""Replay MAME's EEPROM pin traffic through a Python port of rtl/er5911.sv.

Input is the trace written by tools/probe_late.lua (artifacts/system/mame_late.txt,
lines `frame R|W addr value`): writes to 0x6a0000 drive DI/CS/CLK (bits 0/1/2),
reads of 0x48e020 carry DO in bit 8 and READY in bit 9. The model is stepped on
every write and its DO/READY are compared with every read. Exit status is
non-zero on any mismatch, so this doubles as a regression gate for the model.

usage: eeprom_replay.py <rom image> [trace] [-v]
"""
import sys

ROM_EEPROM_OFF = 0x1360000


class ER5911:
    """MAME eeprom_serial_er5911_device (8-bit, 128 cells, 9 address bits)."""
    CMD_BITS = 2 + 9          # opcode + address, after the start bit
    BUSY = 960

    def __init__(self, image):
        self.mem = bytearray(image)
        self.st = 'RESET'
        self.cs = self.clk = self.di = 0
        self.acc = 0
        self.nbits = 0
        self.sh = 0
        self.locked = True
        self.addr = 0
        self.busy = 0
        self.log = []

    def ready(self):
        return self.busy == 0

    def pins(self, cs, clk, di):
        self.di = di
        cs_rise = cs and not self.cs
        cs_fall = (not cs) and self.cs
        clk_rise = clk and not self.clk
        self.cs, self.clk = cs, clk
        if self.busy:
            self.busy -= 1
        if cs_fall:
            self.st = 'RESET'
            return
        if self.st == 'RESET':
            if cs_rise:
                self.st = 'START'
        elif self.st == 'START':
            if clk_rise and di and self.ready() and not cs_rise:
                self.acc = 0
                self.nbits = 0
                self.st = 'CMD'
        elif self.st == 'CMD':
            if clk_rise:
                self.acc = ((self.acc << 1) | di) & 0x7ff
                self.nbits += 1
                if self.nbits == self.CMD_BITS:
                    self.execute()
        elif self.st == 'READ':
            if clk_rise:
                if self.nbits == 0:
                    self.sh = self.mem[self.addr & 0x7f]
                else:
                    self.sh = ((self.sh << 1) | 1) & 0xff
                self.nbits += 1
        elif self.st == 'WDATA':
            if clk_rise:
                self.sh = ((self.sh << 1) | di) & 0xff
                self.nbits += 1
                if self.nbits == 8:
                    self.log.append(('WRITE', self.addr, self.sh, self.locked))
                    if not self.locked:
                        self.mem[self.addr & 0x7f] = self.sh
                        self.busy = self.BUSY
                    self.st = 'WAIT'

    def execute(self):
        op = self.acc >> 9
        self.addr = self.acc & 0x1ff
        self.nbits = 0
        if op == 0:
            sub = self.addr >> 7
            name = ('LOCK', 'INVALID', 'ERASEALL', 'UNLOCK')[sub]
            self.log.append((name, None, None, self.locked))
            if sub == 0:
                self.locked = True
            elif sub == 2 and not self.locked:
                self.mem[:] = b'\xff' * 128
                self.busy = self.BUSY
            elif sub == 3:
                self.locked = False
            self.st = 'RESET' if sub != 2 else 'WAIT'
        elif op == 2:
            self.log.append(('READ', self.addr, self.mem[self.addr & 0x7f], self.locked))
            self.sh = 0          # dummy 0 bit before the first clock
            self.st = 'READ'
        else:
            self.sh = 0
            self.st = 'WDATA'

    def dout(self):
        return (self.sh >> 7) & 1 if self.st == 'READ' else 1


def main():
    argv = [a for a in sys.argv[1:] if not a.startswith('-')]
    verbose = '-v' in sys.argv
    rom = open(argv[0], 'rb').read()
    trace = argv[1] if len(argv) > 1 else 'artifacts/system/mame_late.txt'
    e = ER5911(rom[ROM_EEPROM_OFF:ROM_EEPROM_OFF + 128])
    reads = bad = 0
    for line in open(trace):
        f, k, a, v = line.split()
        v = int(v, 16)
        if k == 'W' and a == '6a0000':
            e.pins((v >> 1) & 1, (v >> 2) & 1, v & 1)
        elif k == 'R' and a == '48e020':
            if (v >> 8) == 0:
                continue        # low-byte access: that is the P2 input port, not IN1
            reads += 1
            mdo, mrdy = (v >> 8) & 1, (v >> 9) & 1
            if (mdo, mrdy) != (e.dout(), int(e.ready())):
                bad += 1
                if verbose or bad <= 10:
                    print(f'mismatch #{bad} read {reads} frame {f}: mame do={mdo} rdy={mrdy}'
                          f' model do={e.dout()} rdy={int(e.ready())} st={e.st} nbits={e.nbits}')
    kinds = {}
    for c in e.log:
        kinds[c[0]] = kinds.get(c[0], 0) + 1
    print(f'{reads} reads, {bad} mismatches; commands: {kinds}')
    if verbose:
        for c in e.log[:80]:
            print('  ', c)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
