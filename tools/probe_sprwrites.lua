-- Where in the frame the game writes its sprite RAM: for each frame in
-- FRAMES, the number of 68000 writes into the sprite window (0x400000-
-- 0x40ffff) while the beam is in the visible area (scanline < 224) and while
-- it is in blanking. tools/dump_state.lua's input schedule, so frames line up.
local want = {}
for n in string.gmatch(os.getenv("FRAMES") or "1300,1500,1850,1900,1950,2000,2100", "%d+") do want[tonumber(n)] = true end
local mach = manager.machine
local sp = mach.devices[":maincpu"].spaces["program"]
local scr
for tag, s in pairs(mach.screens) do scr = s; print("screen " .. tag) end
local vis, blank, f = 0, 0, 0
local ok, err = pcall(function()
  _G.KEEP = _G.KEEP or {}
  _G.KEEP.tap = sp:install_write_tap(0x400000, 0x40ffff, "sprw", function(offset, data, mask)
    local v = scr:vpos()
    if v < 224 then vis = vis + 1 else blank = blank + 1 end
  end)
end)
if not ok then print("tap error: " .. tostring(err)) end
local p1 = mach.ioport.ports[":IN0_P1"]
local coin, start = p1.fields["Coin 1"], p1.fields["1 Player Start"]
local b1, rt, up = p1.fields["P1 Button 1"], p1.fields["P1 Right"], p1.fields["P1 Up"]
_G.KEEP = _G.KEEP or {}
_G.KEEP.n = emu.add_machine_frame_notifier(function()
  if want[f] then print(string.format("frame %d: sprite RAM writes visible=%d blanking=%d", f, vis, blank)) end
  vis, blank = 0, 0
  f = f + 1
  local n = f
  coin:set_value((n > 200 and (n % 120) < 8) and 1 or 0)
  start:set_value((n > 240 and (n % 60) < 8 and (n % 120) >= 8) and 1 or 0)
  if n > 400 then
    b1:set_value((n % 11 < 4) and 1 or 0); rt:set_value((n % 97 < 40) and 1 or 0); up:set_value((n % 53 < 20) and 1 or 0)
  end
end)
