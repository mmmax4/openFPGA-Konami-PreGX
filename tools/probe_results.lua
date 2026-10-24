-- MAME's self-test results screen: snapshots at 15 s and 20 s, plus PC per frame.
local mach = manager.machine
local cpu  = mach.devices[":maincpu"]
local f = 0
local out = io.open("artifacts/system/mame_boot_pc1560.txt", "w")
_G.KEEP = {}
_G.KEEP.n = emu.add_machine_frame_notifier(function()
  f = f + 1
  out:write(string.format("frame %d: pc=%06x\n", f, cpu.state["PC"].value))
  if f == 1250 or f == 1275 then mach.video:snapshot() end
end)
_G.KEEP.s = emu.add_machine_stop_notifier(function() out:close() end)
