-- Dump slices of every ROM region so the built .rom image can be verified
-- against what MAME actually loads. Byte-by-byte over 20 MB would be far too
-- slow in Lua, so we take generous slices at region start, middle and end,
-- which is enough to catch any interleave/order/endian mistake.
local regs = manager.machine.memory.regions
local plan = {
  {":maincpu",  0x300000},
  {":soundcpu", 0x040000},
  {":k056832",  0x280000},
  {":k055673",  0x800000},
  {":gfx3",     0x180000},
  {":gfx4",     0x0a0000},
  {":k054539",  0x400000},
  {":eeprom",   0x000080},
}
local SLICE = 0x1000
local f = assert(io.open("artifacts/mame_regions.txt", "w"))
for _, e in ipairs(plan) do
  local tag, size = e[1], e[2]
  local r = regs[tag]
  if r == nil then
    f:write(string.format("MISSING %s\n", tag))
  else
    f:write(string.format("REGION %s size=%d actual=%d\n", tag, size, r.size))
    -- the K056832 region is stored as 5-byte groups; slices must start on a
    -- group boundary or the image comparison cannot line them up
    local align = (tag == ":k056832") and 5 or 1
    local n = math.min(SLICE, size)
    local starts = { 0, math.floor(size/3), math.floor(2*size/3), size - n }
    for _, off in ipairs(starts) do
      off = off - (off % align)
      if off >= 0 and off + n <= r.size then
        local t = {}
        for i = 0, n-1 do t[i+1] = string.format("%02x", r:read_u8(off+i)) end
        f:write(string.format("SLICE %s %d\n%s\n", tag, off, table.concat(t)))
      end
    end
  end
end
f:close()
print("REGIONS_DUMPED")
manager.machine:exit()
