-- Original EAA control writes. All pass-through callbacks return no value.
local m = manager.machine
local dir = assert(os.getenv('DUMP_DIR'))
local sp = m.devices[':maincpu'].spaces['program']
local first = tonumber(assert(os.getenv('TRACE_FIRST')))
local last = tonumber(assert(os.getenv('TRACE_LAST')))
local frame, calls, errors = 0, 0, 0
local log = assert(io.open(dir .. '/controls.txt', 'w'))
local pc_entry, pc_key
for _, key in ipairs({'PC', 'CURPC', 'GENPC', 'pc'}) do
    local value = m.devices[':maincpu'].state[key]
    if value then pc_entry = value; pc_key = key; break end
end
local function stamp()
    local ok, time = pcall(function() return m.time:as_double() end)
    if not ok then time = -1 end
    local pc = pc_entry and pc_entry.value or -1
    return time, pc
end
local function install()
    local time, pc = stamp()
    print(string.format('CONTROL_API time=%.12f pc_key=%s pc=%x', time, tostring(pc_key), pc))
    assert(time >= 0 and pc >= 0, 'Timestamp and original CPU program counter required')
    for _, block in ipairs({{0x400000,0x40ffff,'SPRITE_W0'}, {0x480000,0x4800ff,'K55'}, {0x482010,0x48201f,'K47'},
            {0x484000,0x484007,'K46'}, {0x48a000,0x48a01f,'K38'},
            {0x48c000,0x48c03f,'K56'}, {0x700000,0x70027f,'PALETTE_LOW'}}) do
        local name = block[3]
        _G.CONTROL_KEEP[name] = sp:install_write_tap(block[1], block[2], 'readonly_' .. name,
            function(off, data, mask)
                if frame < first or frame > last then return end
                if name == 'SPRITE_W0' and ((off - 0x400000) & 255) ~= 0 then return end
                local ok, error = pcall(function()
                    local t, p = stamp()
                    assert(t >= 0 and p >= 0)
                    calls = calls + 1
                    log:write(string.format('%d %.12f %x %s %06x %04x %04x\n', frame, t, p, name, off, data, mask))
                end)
                if not ok then
                    errors = errors + 1
                    if errors <= 8 then log:write('TRACE_ERROR ' .. tostring(error) .. '\n'); log:flush() end
                end
            end)
    end
    print('CONTROL_INSTALLED frame=' .. frame)
end
_G.CONTROL_KEEP = {}
_G.CONTROL_KEEP.frame = emu.register_frame(function()
    frame = frame + 1
    if frame == first then install() end
end)
_G.CONTROL_KEEP.stop = emu.register_stop(function()
    log:close()
    print(string.format('CONTROL_END frames=%d calls=%d errors=%d', frame, calls, errors))
end)
