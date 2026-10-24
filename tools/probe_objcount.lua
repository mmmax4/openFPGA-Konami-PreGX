-- How many sprite entries are live at the instants that matter: at the
-- frame notifier and at frame_done (the screen just rendered), with the beam
-- position, for frames listed in FRAMES (default 1290..1310,1600).
local want = {}
for n in string.gmatch(os.getenv("FRAMES") or "1290,1300,1310,1500,1600", "%d+") do want[tonumber(n)] = true end
local mach = manager.machine
local sp = mach.devices[":maincpu"].spaces["program"]
local scr = mach.screens[":screen"]
local function live()
  local n = 0
  for e = 0, 255 do
    local w0 = sp:read_u16(0x400000 + ((e * 8) << 5))
    if w0 & 0x8000 ~= 0 then n = n + 1 end
  end
  return n
end
local f = 0
_G.KEEP = {}
_G.KEEP.n = emu.add_machine_frame_notifier(function()
  if want[f] then print(string.format("frame %d notifier: vpos=%s live=%d", f, tostring(scr.vpos), live())) end
  f = f + 1
end)
_G.KEEP.d = emu.register_frame_done(function()
  if want[f] then print(string.format("frame %d frame_done: vpos=%s live=%d", f, tostring(scr.vpos), live())) end
end)
