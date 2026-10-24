-- Freeze one frame of Gaiapolis and write everything the reference renderer
-- needs, alongside MAME's own snapshot of that same frame.
--
--   DUMPF=<frame>   frame to capture (default 9000)
--   DUMPNAME=<tag>  name for the state file (default "state")
--   FORCE_ENABLE=<hex>  override the K055555 layer-enable register, so a
--                       single layer can be isolated for diffing
--
-- Write-only chip registers are shadowed through write taps. VRAM is 17 pages
-- of 4 KB behind a bank register, so after the snapshot is taken (and only
-- then, because it perturbs the chip) we cycle the bank and read all of it.

local mach = manager.machine
local sp   = mach.devices[":maincpu"].spaces["program"]
local KEEP = {}
_G.DUMPKEEP = KEEP

local function newregs(n) local t = {} for i = 0, n-1 do t[i] = 0 end return t end

local k56_regs  = newregs(32)    -- VACSET   0x480000, word
local k56_regsb = newregs(4)     -- VSCCS    0x482000, word
local k46_regs  = newregs(8)     -- K053246  0x430000, byte pairs
local k47_regs  = newregs(8)     -- K055673  0x450010, word
local k55_regs  = newregs(48)    -- K055555  0x488000, byte in low or high half
local k38_regs  = newregs(16)    -- K054338  0x48C000, word
local roz_ctrl  = newregs(2)     -- 0x6C0000 enable/bank, 0x484000 clip
local roz_clip  = newregs(2)

local FORCE_ENABLE = os.getenv("FORCE_ENABLE")
if FORCE_ENABLE then FORCE_ENABLE = tonumber(FORCE_ENABLE, 16) end

KEEP.t1 = sp:install_write_tap(0x480000, 0x48003f, "k56", function(off, data, mask)
  k56_regs[(off - 0x480000) // 2] = data & 0xffff end)
KEEP.t2 = sp:install_write_tap(0x482000, 0x482007, "k56b", function(off, data, mask)
  k56_regsb[(off - 0x482000) // 2] = data & 0xffff end)
KEEP.t3 = sp:install_write_tap(0x430000, 0x430007, "k46", function(off, data, mask)
  local w = (off - 0x430000) // 2
  k46_regs[w*2] = (data >> 8) & 0xff; k46_regs[w*2+1] = data & 0xff end)
KEEP.t4 = sp:install_write_tap(0x450010, 0x45001f, "k47", function(off, data, mask)
  k47_regs[(off - 0x450010) // 2] = data & 0xffff end)
KEEP.t5 = sp:install_write_tap(0x488000, 0x4880ff, "k55", function(off, data, mask)
  -- K055555_word_w: mem_mask 0x00ff -> low byte, else high byte
  local r = (off - 0x488000) // 2
  local v
  if mask == 0x00ff then v = data & 0xff else v = (data >> 8) & 0xff end
  if r < 48 then k55_regs[r] = v end
  -- layer isolation: rewrite the ENABLE register (45) on its way to the chip
  if FORCE_ENABLE and r == 45 then
    if mask == 0x00ff then return (data & 0xff00) | FORCE_ENABLE
    else return (data & 0x00ff) | (FORCE_ENABLE << 8) end
  end
end)
KEEP.t6 = sp:install_write_tap(0x48c000, 0x48c01f, "k38", function(off, data, mask)
  k38_regs[(off - 0x48c000) // 2] = data & 0xffff end)
KEEP.t7 = sp:install_write_tap(0x6c0000, 0x6c0001, "rozen", function(off, data, mask)
  roz_ctrl[0] = data & 0xffff end)
KEEP.t8 = sp:install_write_tap(0x484000, 0x484003, "rozclip", function(off, data, mask)
  roz_clip[(off - 0x484000) // 2] = data & 0xffff end)

local DUMPF = tonumber(os.getenv("DUMPF") or "9000")
local NAME  = os.getenv("DUMPNAME") or "state"
local f = 0

local function hexrun(read, n)
  local t = {}
  for i = 1, n do t[i] = string.format("%04x", read(i-1)) end
  return table.concat(t, " ")
end

local function dump()
  mach.video:snapshot()

  local out = assert(io.open("artifacts/states/" .. NAME .. ".txt", "w"))
  out:write("# gaiapolis frozen state, frame ", tostring(f), "\n")
  out:write("FRAME ", tostring(f), "\n")

  local function regline(name, t, n)
    local a = {}
    for i = 0, n-1 do a[i+1] = string.format("%04x", t[i]) end
    out:write(name, " ", table.concat(a, " "), "\n")
  end
  regline("K56REGS",  k56_regs, 32)
  regline("K56REGSB", k56_regsb, 4)
  regline("K46REGS",  k46_regs, 8)
  regline("K47REGS",  k47_regs, 8)
  regline("K55REGS",  k55_regs, 48)
  regline("K38REGS",  k38_regs, 16)
  regline("ROZCTRL",  roz_ctrl, 1)
  regline("ROZCLIP",  roz_clip, 2)

  -- palette: 2048 entries, two 16-bit words each
  out:write("PALETTE ", hexrun(function(i) return sp:read_u16(0x420000 + i*2) end, 4096), "\n")

  -- ROZ control block and line RAM. 0x460000 is mapped .writeonly(), so a CPU
  -- read returns open bus -- these have to come from the memory shares.
  local shares = mach.memory.shares
  local ct = shares[":k053936_0_ct16"]
  local li = shares[":k053936_0_li16"]
  out:write("ROZCT16 ", hexrun(function(i) return ct:read_u16(i*2) end, 16), "\n")
  out:write("ROZLI16 ", hexrun(function(i) return li:read_u16(i*2) end, 1024), "\n")

  -- sprite RAM: k053247 word w lives at 0x400000 + ((w & 0x7f8) << 5) + (w & 7)*2
  out:write("SPRITERAM ", hexrun(function(w)
      return sp:read_u16(0x400000 + ((w & 0x7f8) << 5) + (w & 7) * 2)
    end, 2048), "\n")

  -- VRAM: 17 pages of 0x1000 words behind the bank register at 0x480032.
  -- Done last: it perturbs the chip, and we exit straight after.
  local saved_r0  = k56_regs[0]
  local saved_r19 = k56_regs[0x19]
  -- diagnostic: the page the CPU currently has selected, read before we touch
  -- the bank register, so a broken bank cycle is visible in the dump
  out:write("CURPAGE ", hexrun(function(i) return sp:read_u16(0x410000 + i*2) end, 4096), "\n")
  for page = 0, 15 do
    local col, row = page & 3, (page >> 2) & 3
    sp:write_u16(0x480000, saved_r0 & ~0x0002)      -- internal linescroll
    sp:write_u16(0x480032, (row << 3) | col)
    out:write(string.format("VRAM %d ", page),
              hexrun(function(i) return sp:read_u16(0x410000 + i*2) end, 4096), "\n")
  end
  sp:write_u16(0x480000, saved_r0 | 0x0002)         -- external linescroll page
  out:write("VRAM 16 ", hexrun(function(i) return sp:read_u16(0x410000 + i*2) end, 4096), "\n")
  sp:write_u16(0x480000, saved_r0)
  sp:write_u16(0x480032, saved_r19)

  out:close()
  print("DUMPED " .. NAME .. " frame " .. tostring(f))
  io.stdout:flush()
end

-- input driver: same schedule as probe_sprites.lua so frame numbers line up
local p1 = mach.ioport.ports[":IN0_P1"]
local coin, start = p1.fields["Coin 1"], p1.fields["1 Player Start"]
local b1, rt, up = p1.fields["P1 Button 1"], p1.fields["P1 Right"], p1.fields["P1 Up"]

KEEP.notif = emu.add_machine_frame_notifier(function()
  f = f + 1
  local n = f
  coin:set_value((n > 200 and (n % 120) < 8) and 1 or 0)
  start:set_value((n > 240 and (n % 60) < 8 and (n % 120) >= 8) and 1 or 0)
  if n > 400 then
    b1:set_value((n % 11 < 4) and 1 or 0)
    rt:set_value((n % 97 < 40) and 1 or 0)
    up:set_value((n % 53 < 20) and 1 or 0)
  end
  if f == DUMPF then dump(); mach:exit() end
end)
