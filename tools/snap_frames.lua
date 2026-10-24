-- Save MAME snapshots at the frames listed in SNAPFRAMES (comma-separated),
-- for comparing the RTL's attract-mode frames by eye:
--   SNAPFRAMES=1400,1500,1600 mame gaiapols ... -snapshot_directory artifacts/system/mame_attract \
--        -autoboot_script tools/snap_frames.lua -seconds_to_run 28
local want = {}
for n in string.gmatch(os.getenv("SNAPFRAMES") or "1400,1500,1600", "%d+") do want[tonumber(n)] = true end
local f = 0
_G.KEEP = {}
_G.KEEP.n = emu.add_machine_frame_notifier(function()
    if want[f] then manager.machine.video:snapshot() end
    f = f + 1
end)
