-- What the game does with the service-mode switch: SVC_FROM=<frame> turns it
-- on from that frame (0 = from power-up), snapshots at SNAPFRAMES.
local want = {}
for n in string.gmatch(os.getenv("SNAPFRAMES") or "1400,1500,1700,1900", "%d+") do want[tonumber(n)] = true end
local from = tonumber(os.getenv("SVC_FROM") or "0")
local mach = manager.machine
local p1 = mach.ioport.ports[":IN0_P1"]
local svc = p1.fields["Service Mode"]
local in1 = mach.ioport.ports[":IN1"]
local svc2 = in1 and in1.fields["Service Mode"]
local f = 0
_G.KEEP = {}
_G.KEEP.n = emu.add_machine_frame_notifier(function()
  local on = (f >= from) and 1 or 0
  if svc then svc:set_value(on) end
  if svc2 then svc2:set_value(on) end
  if want[f] then mach.video:snapshot() end
  f = f + 1
end)
print("fields: IN0 " .. tostring(svc ~= nil) .. " IN1 " .. tostring(svc2 ~= nil))
