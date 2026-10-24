-- Original EAA program/MMIO timing diagnostic. Read-only taps, no game inputs.
local m = manager.machine
local dir = assert(os.getenv('DUMP_DIR'))
local cpu = m.devices[':maincpu']
local sp = cpu.spaces['program']
local frame, events, falls, namewrites, calls, errors = 0, 0, 0, 0, 0, 0
local first, last = 3940, 4100
local regs = emu.item(assert(m.devices[':k055673'].items['0/m_kx46_regs']))
local ram = emu.item(assert(m.devices[':k055673'].items['0/m_ram']))
assert(regs.size == 1 and regs.count == 8 and ram.size == 2 and ram.count >= 2048)
local log = assert(io.open(dir .. '/writes.txt', 'w'))
local function pc()
    local ok, v = pcall(function() return cpu.state['PC'].value end)
    return ok and tonumber(v) or -1
end
local function checked(callback)
    return function(...)
        local ok, message = pcall(callback, ...)
        if not ok then
            errors = errors + 1
            if errors <= 8 then log:write('TRACE_ERROR ' .. tostring(message) .. '\n'); log:flush() end
        end
        -- No return: the pass-through tap must never modify game data.
    end
end
local function binary(path, count, size, read)
    local out = assert(io.open(path, 'wb'))
    local bytes = {}
    for i = 0, count - 1 do
        local v = read(i)
        for b = 0, size - 1 do bytes[#bytes + 1] = string.char((v >> (b*8)) & 255) end
    end
    out:write(table.concat(bytes)); out:close()
end
local function snapshot(data)
    events = events + 1
    local prefix = string.format('%s/e%04d-f%05d-', dir, events, frame)
    binary(prefix .. 'k47-list.bin', 2048, 2, function(i) return ram:read(i) end)
    binary(prefix .. 'cpu-spriteram.bin', 32768, 2, function(i) return sp:read_u16(0x400000 + 2*i) end)
    log:write(string.format('EVENT %d frame=%d pc=%x register=%02x new=%02x\n',
        events, frame, pc(), regs:read(5), data))
    log:flush()
end
_G.DMA_KEEP = {}
local previous
local function install()
previous = regs:read(5)
_G.DMA_KEEP.reg = sp:install_write_tap(0x484004, 0x484005, 'readonly_objset1', checked(function(off, data, mask)
    calls = calls + 1
    log:write(string.format('RAWREG frame=%d off=%x data=%x mask=%x\n', frame, off, data, mask))
    if frame < first or frame > last or (mask & 255) == 0 then return end
    local old, new = previous, data & 255
    log:write(string.format('OBJSET1 frame=%d pc=%x data=%04x mask=%04x previous=%02x register=%02x\n',
        frame, pc(), data, mask, old, regs:read(5)))
    previous = new
    if (old & 16) ~= 0 and (new & 16) == 0 then
        falls = falls + 1
        snapshot(new)
    end
end))
_G.DMA_KEEP.ram = sp:install_write_tap(0x400000, 0x40ffff, 'readonly_sprite_writes', checked(function(off, data, mask)
    calls = calls + 1
    if calls <= 32 then log:write(string.format('RAW frame=%d off=%x data=%x mask=%x\n', frame, off, data, mask)) end
    if frame < first or frame > last then return end
    -- Record all scattered word0 writes, including transient deactivate/clear.
    if ((off - 0x400000) & 255) == 0 then
        log:write(string.format('W0 frame=%d pc=%x address=%06x data=%04x mask=%04x\n',
            frame, pc(), off, data, mask))
        namewrites = namewrites + 1
    end
end))
print('DMA_TAPS_INSTALLED frame=' .. frame)
end
_G.DMA_KEEP.frame = emu.register_frame(function()
    frame = frame + 1
    -- Install after boot/reset handler changes have finished.
    if frame == first then install() end
end)
_G.DMA_KEEP.stop = emu.register_stop(function()
    log:close()
    print(string.format('DMA_END frames=%d events=%d falls=%d word0writes=%d calls=%d errors=%d', frame, events, falls, namewrites, calls, errors))
end)
