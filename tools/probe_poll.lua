-- 68000 pacing oracle: while the self-test waits for the Z80 (the bmi loop at
-- 201daa polling K054321 latch 2), count the polls per frame. The loop is
-- memory-bound, so its rate is the 68000's effective bus speed; the RTL's
-- token pacing (gaia_main STEP_COST/STEP_GAIN) is set to match it.
-- Output: artifacts/system/mame_poll.txt, "frame polls"
local mach = manager.machine
local sp = mach.devices[":maincpu"].spaces["program"]
local f, n = 0, 0
local out = io.open("artifacts/system/mame_poll.txt", "w")
_G.KEEP = {}
_G.KEEP.r = sp:install_read_tap(0x48a014, 0x48a015, "lat2", function(o, d, m) n = n + 1 end)
_G.KEEP.n = emu.add_machine_frame_notifier(function()
    out:write(string.format("%d %d\n", f, n)); f = f + 1; n = 0
    if f % 100 == 0 then out:flush() end
end)
_G.KEEP.s = emu.add_machine_stop_notifier(function() out:close() end)
