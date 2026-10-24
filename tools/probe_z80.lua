-- Z80 boot timeline: per frame the sound CPU's PC, how many bytes it pulled
-- through each K054539's streaming port (e22d / e62d), latch writes to the
-- 68000 (f000-f003) and sound_ctrl writes (f800), for comparing the RTL sound
-- board's boot against MAME's. Output: artifacts/system/mame_z80.txt
local mach = manager.machine
local z = mach.devices[":soundcpu"]
local sp = z.spaces["program"]
local f, n1, n2 = 0, 0, 0
local out = io.open("artifacts/system/mame_z80.txt", "w")
_G.KEEP = {}
_G.KEEP.r1 = sp:install_read_tap(0xe22d, 0xe22d, "s1", function(o, d, m) n1 = n1 + 1 end)
_G.KEEP.r2 = sp:install_read_tap(0xe62d, 0xe62d, "s2", function(o, d, m) n2 = n2 + 1 end)
for i, base in ipairs({0xe000, 0xe400}) do
    _G.KEEP["k" .. i] = sp:install_write_tap(base + 0x214, base + 0x22f, "k5" .. i, function(o, d, m)
        local lo = o - base
        if lo == 0x214 or lo == 0x215 or lo == 0x22c or lo == 0x22e or lo == 0x22f then
            out:write(string.format("%d W %04x %02x\n", f, o, d))
        end
    end)
end
_G.KEEP.w1 = sp:install_write_tap(0xf000, 0xf003, "lat", function(o, d, m) out:write(string.format("%d LAT %04x %02x\n", f, o, d)) end)
_G.KEEP.w2 = sp:install_write_tap(0xf800, 0xf800, "ctl", function(o, d, m) out:write(string.format("%d CTL %02x\n", f, d)) end)
_G.KEEP.n = emu.add_machine_frame_notifier(function()
    out:write(string.format("%d PC %04x s1=%d s2=%d\n", f, z.state["PC"].value, n1, n2))
    f = f + 1; n1 = 0; n2 = 0
    if f % 100 == 0 then out:flush() end
end)
_G.KEEP.s = emu.add_machine_stop_notifier(function() out:close() end)
