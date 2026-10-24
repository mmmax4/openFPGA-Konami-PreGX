-- Accesses to the K054000 (660000-66003f) and the EEPROM/IN1 port (48e020)
-- over the whole boot, reads and writes, with values -- for the items the
-- self-test runs after the ROM checks.
local mach = manager.machine
local sp = mach.devices[":maincpu"].spaces["program"]
local f = 0
local out = io.open("artifacts/system/mame_late.txt", "w")
_G.KEEP = {}
_G.KEEP.r1 = sp:install_read_tap(0x660000, 0x66003f, "k000r", function(o, d, m) out:write(string.format("%d R %06x %04x\n", f, o, d)) end)
_G.KEEP.w1 = sp:install_write_tap(0x660000, 0x66003f, "k000w", function(o, d, m) out:write(string.format("%d W %06x %04x\n", f, o, d)) end)
_G.KEEP.r2 = sp:install_read_tap(0x48e020, 0x48e023, "eepr", function(o, d, m) out:write(string.format("%d R %06x %04x\n", f, o, d)) end)
_G.KEEP.w2 = sp:install_write_tap(0x6a0000, 0x6a0001, "eepw", function(o, d, m) out:write(string.format("%d W %06x %04x\n", f, o, d)) end)
_G.KEEP.n = emu.add_machine_frame_notifier(function() f = f + 1 if f % 100 == 0 then out:flush() end end)
_G.KEEP.s = emu.add_machine_stop_notifier(function() out:close() end)
