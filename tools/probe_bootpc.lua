-- Boot reference: MAME's 68000 PC at the end of every frame, and snapshots at
-- chosen frames, so the RTL's boot can be compared frame for frame.
local mach = manager.machine
local cpu  = mach.devices[":maincpu"]
local f = 0
local out = io.open("artifacts/system/mame_boot_pc600.txt", "w")
local snaps = { [60]=true, [120]=true, [180]=true, [300]=true, [420]=true, [540]=true }
_G.KEEP = {}
_G.KEEP.n = emu.add_machine_frame_notifier(function()
  f = f + 1
  out:write(string.format("frame %d: pc=%06x sr=%04x\n", f, cpu.state["PC"].value, cpu.state["SR"].value))
  if snaps[f] then mach.video:snapshot() end
  if f % 20 == 0 then out:flush() end
end)
_G.KEEP.s = emu.add_machine_stop_notifier(function() out:close() end)
