-- Read-only comparison of original Mystic Warriors EAA across MAME runtimes.
-- No inputs, game-memory writes, save imports, or ROM patches.
local m = type(manager.machine) == "function" and manager:machine() or manager.machine
local dir = assert(os.getenv("DUMP_DIR"))
local sp = m.devices[":maincpu"].spaces["program"]
local frame, captured = 0, 0
local wanted = {}
for f in assert(os.getenv("DUMPFRAMES")):gmatch("%d+") do wanted[tonumber(f)] = true end
local function item(dev, name, size, count)
    local it = emu.item(assert(m.devices[dev].items["0/" .. name]))
    assert(it.size == size and (it.count == count or (name == "m_ram" and it.count == 8192)),
        string.format("unexpected shape %s size=%d count=%d", name, it.size, it.count))
    print(string.format("NAMES_ITEM %s size=%d count=%d", name, it.size, it.count))
    return it
end
local plan = {
    {"k46_regs", item(":k055673", "m_kx46_regs", 1, 8)},
    {"k47_regs", item(":k055673", "m_kx47_regs", 2, 16)},
    {"k47_list", item(":k055673", "m_ram", 2, 2048)},
    {"k55_regs", item(":k055555", "m_regs", 1, 128)},
    {"k38_regs", item(":k054338", "m_regs", 2, 32)},
    {"k56_regs", item(":k056832", "m_regs", 2, 32)}
}
local function binary(path, count, size, read)
    local out = assert(io.open(path, "wb"))
    local bytes = {}
    for i = 0, count - 1 do
        local v = read(i)
        for b = 0, size - 1 do bytes[#bytes + 1] = string.char((v >> (b*8)) & 255) end
    end
    out:write(table.concat(bytes)); out:close()
end
local function on_frame()
    frame = frame + 1
    if not wanted[frame] then return end
    local prefix = string.format("%s/f%05d-", dir, frame)
    for _, entry in ipairs(plan) do
        local it = entry[2]
        binary(prefix .. entry[1] .. ".bin", it.count, it.size, function(i) return it:read(i) end)
    end
    binary(prefix .. "palette.bin", 4096, 2, function(i) return sp:read_u16(0x700000 + 2*i) end)
    binary(prefix .. "cpu-spriteram.bin", 32768, 2, function(i) return sp:read_u16(0x400000 + 2*i) end)
    local pixels, w, h = m.screens[":screen"]:pixels()
    if not w then w, h = m.screens[":screen"]:width(), m.screens[":screen"]:height() end
    assert(type(pixels) == "string" and #pixels == w*h*4)
    local out = assert(io.open(prefix .. "pixels-current.bin", "wb"))
    out:write(pixels); out:close()
    print(string.format("NAMES_FRAME %d %d %d", frame, w, h))
    captured = captured + 1
end
local register_frame = emu.add_machine_frame_notifier or emu.register_frame
local register_stop = emu.add_machine_stop_notifier or emu.register_stop
_G.NAMES_KEEP = {frame=register_frame(on_frame), stop=register_stop(function()
    print(string.format("NAMES_END frames=%d captures=%d", frame, captured))
end)}
