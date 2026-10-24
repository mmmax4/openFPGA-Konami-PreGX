-- 68000 timeline: the main CPU's PC sampled once a frame, for comparing the
-- RTL's boot phase by phase (sim/run_system.sh's trace has the same view).
-- Output: artifacts/system/mame_68k.txt, "frame pc"
local mach = manager.machine
local cpu = mach.devices[":maincpu"]
local f = 0
local out = io.open("artifacts/system/mame_68k.txt", "w")
_G.KEEP = {}
_G.KEEP.n = emu.add_machine_frame_notifier(function()
    out:write(string.format("%d %06x\n", f, cpu.state["PC"].value)); f = f + 1
    if f % 100 == 0 then out:flush() end
end)
_G.KEEP.s = emu.add_machine_stop_notifier(function() out:close() end)
