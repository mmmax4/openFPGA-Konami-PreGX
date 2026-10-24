local f = 0
local shots = 0
emu.add_machine_frame_notifier(function()
  f = f + 1
  if f % 300 == 0 and shots < 12 then
    manager.machine.video:snapshot()
    shots = shots + 1
  end
  if f >= 3700 then manager.machine:exit() end
end)
