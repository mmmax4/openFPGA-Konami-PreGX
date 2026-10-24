-- Log every 68000 read of a device window during the self-test, with the
-- value MAME returned, so the RTL's reads can be diffed against them.
-- Windows: 400000-5fffff (video chips, RAM) and 610000-6fffff (K054000,
-- EEPROM, misc); work RAM and program ROM are left out.
local mach = manager.machine
local sp = mach.devices[":maincpu"].spaces["program"]
local F0, F1 = tonumber(os.getenv("F0") or "90"), tonumber(os.getenv("F1") or "170")
local f = 0
local out = io.open(os.getenv("OUT") or "artifacts/system/mame_reads.txt", "w")
_G.KEEP = {}
local function tap(lo, hi, name)
  return sp:install_read_tap(lo, hi, name, function(offset, data, mask)
    if f >= F0 and f <= F1 then
      out:write(string.format("%d %06x %04x %04x\n", f, offset, data, mask))
    end
  end)
end
_G.KEEP.t1 = tap(0x400000, 0x5fffff, "rd_a")
_G.KEEP.t2 = tap(0x610000, 0x6fffff, "rd_b")
_G.KEEP.n = emu.add_machine_frame_notifier(function() f = f + 1 if f > F1 + 1 then out:close() mach:exit() end end)
