-- Measure per-scanline sprite load for gaiapolis (Konami pre-GX / mystwarr hw).
-- Sprite table: 256 entries x 8 words, reachable through the 68k "scattered"
-- window at 0x400000: word w -> byte 0x400000 + ((w & 0x7f8) << 5) + (w & 7)*2
local mach = manager.machine
local cpu  = mach.devices[":maincpu"]
local sp   = cpu.spaces["program"]

local DX, DY = -61, -22          -- k055673 set_config(K055673_LAYOUT_RNG, -61, -22)
local VIS_W, VIS_H = 376, 224

local k46 = {}                    -- k053246 regs captured from writes
for i=0,7 do k46[i]=0 end
-- NOTE: taps and notifiers are unsubscribed if their handle is collected.
_G.KEEP = {}
_G.KEEP.tap = sp:install_write_tap(0x430000, 0x430007, "k46", function(offset, data, mask)
  local w = (offset - 0x430000) // 2      -- word index 0..3 -> regs 2w, 2w+1
  k46[w*2]   = (data >> 8) & 0xff
  k46[w*2+1] = data & 0xff
end)

local function s16(v) if v >= 0x8000 then return v - 0x10000 end return v end

local f = 0
-- CSVOUT lets this script be reused purely as an input driver (for
-- snapshot and state captures) without clobbering the measurement.
local out = io.open(os.getenv("CSVOUT") or "artifacts/sprite_load.csv", "w")
out:write("frame,active,onscreen,max_dst_px_line,max_src_px_line,sum_dst_px,max_sprites_line\n")

-- running worst-case across the whole session
local W = { dst=0, src=0, spr=0, frame=0, active=0 }

local function frame_cb()
  f = f + 1
  if f % 6 ~= 0 then return end

  local dst = {}                    -- per raster line: destination pixels written
  local src = {}                    -- per raster line: source pixels fetched
  local cnt = {}
  for y = 0, VIS_H-1 do dst[y]=0; src[y]=0; cnt[y]=0 end

  local offx = s16((k46[0] << 8) | k46[1])
  local offy = s16((k46[2] << 8) | k46[3])
  local flipscreenx = k46[5] & 1
  local flipscreeny = (k46[5] >> 1) & 1

  local active, onscreen = 0, 0
  local sumdst = 0

  for n = 0, 255 do
    local base = 0x400000 + (n << 12)          -- (offs<<5) with offs = n*8 -> n<<8... see below
    -- word w = n*8 + k  ->  byte 0x400000 + ((n*8) << 5) + k*2 = 0x400000 + (n<<8) + k*2
    base = 0x400000 + (n << 8)
    local w0 = sp:read_u16(base + 0)
    if (w0 & 0x8000) ~= 0 then
      active = active + 1
      local oy   = sp:read_u16(base + 4) & 0x3ff
      local ox   = sp:read_u16(base + 6) & 0x3ff
      local zyr  = sp:read_u16(base + 8) & 0x3ff
      local zxr  = sp:read_u16(base + 10) & 0x3ff

      local zoomy = (zyr ~= 0) and ((0x400000 + (zyr >> 1)) // zyr) or 0x800000
      local zoomx
      local scalex, scaley = zxr, zyr
      if (w0 & 0x4000) ~= 0 then zoomx = zoomy; scalex = scaley
      else zoomx = (zxr ~= 0) and ((0x400000 + (zxr >> 1)) // zxr) or 0x800000 end

      local sz = (w0 >> 8) & 0x0f
      local wt = 1 << (sz & 3)          -- width in 16x16 tiles
      local ht = 1 << ((sz >> 2) & 3)

      if flipscreenx ~= 0 then ox = -ox end
      if flipscreeny ~= 0 then oy = -oy end

      -- wrap (k053247 opset bit 6 unknown from lua; use the 1024 case, the common one)
      local wrapsize, xwraplim, ywraplim = 1024, 1024-384, 1024-512
      ox = (ox - offx) & (wrapsize-1)
      oy = ((-oy) - offy) & (wrapsize-1)
      if ox >= xwraplim then ox = ox - wrapsize end
      if oy >= ywraplim then oy = oy - wrapsize end

      ox = ox + DX
      oy = oy - DY

      local dw = (zoomx * wt) >> 12     -- destination width in pixels
      local dh = (zoomy * ht) >> 12
      ox = ox - ((zoomx * wt) >> 13)
      oy = oy - ((zoomy * ht) >> 13)

      -- raster X is the 376 axis, raster Y the 224 axis
      local x0, x1 = ox, ox + dw - 1
      local y0, y1 = oy, oy + dh - 1
      if x1 >= 0 and x0 < VIS_W and y1 >= 0 and y0 < VIS_H and dw > 0 and dh > 0 then
        onscreen = onscreen + 1
        local cx0 = math.max(x0, 0)
        local cx1 = math.min(x1, VIS_W-1)
        local visw = cx1 - cx0 + 1
        local srcw = math.min(visw, wt * 16)   -- source pixels actually fetched per line
        local cy0 = math.max(y0, 0)
        local cy1 = math.min(y1, VIS_H-1)
        for y = cy0, cy1 do
          dst[y] = dst[y] + visw
          src[y] = src[y] + srcw
          cnt[y] = cnt[y] + 1
          sumdst = sumdst + visw
        end
      end
    end
  end

  local md, ms, mc = 0, 0, 0
  for y = 0, VIS_H-1 do
    if dst[y] > md then md = dst[y] end
    if src[y] > ms then ms = src[y] end
    if cnt[y] > mc then mc = cnt[y] end
  end
  out:write(string.format("%d,%d,%d,%d,%d,%d,%d\n", f, active, onscreen, md, ms, sumdst, mc))
  if f % 300 == 0 then out:flush() end
  if md > W.dst then W.dst = md; W.frame = f; W.active = active end
  if ms > W.src then W.src = ms end
  if mc > W.spr then W.spr = mc end
end

-- drive the game: coin, start, then wiggle so we reach real gameplay
local p1 = mach.ioport.ports[":IN0_P1"]
local coin  = p1.fields["Coin 1"]
local start = p1.fields["1 Player Start"]
local b1    = p1.fields["P1 Button 1"]
local rt    = p1.fields["P1 Right"]
local up    = p1.fields["P1 Up"]

local STOP = tonumber(os.getenv("STOPF") or "9000")

_G.KEEP.notif = emu.add_machine_frame_notifier(function()
  local n = f + 1
  -- coin repeatedly and mash start until play begins
  coin:set_value((n > 200 and (n % 120) < 8) and 1 or 0)
  start:set_value((n > 240 and (n % 60) < 8 and (n % 120) >= 8) and 1 or 0)
  if n > 400 then
    b1:set_value((n % 11 < 4) and 1 or 0)
    rt:set_value((n % 97 < 40) and 1 or 0)
    up:set_value((n % 53 < 20) and 1 or 0)
  end
  frame_cb()
end)

_G.KEEP.stop = emu.add_machine_stop_notifier(function()
  out:write(string.format("# WORST dst=%d src=%d sprites=%d at frame %d (active=%d) frames=%d\n",
      W.dst, W.src, W.spr, W.frame, W.active, f))
  out:close()
  print(string.format("WORST_DST_PX_PER_LINE=%d WORST_SRC_PX_PER_LINE=%d WORST_SPRITES_PER_LINE=%d FRAMES=%d",
      W.dst, W.src, W.spr, f))
  io.stdout:flush()
end)
