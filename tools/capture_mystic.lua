-- Private, read-only state/audio capture for the historical local MAME 0.220.
-- No game data writes; input events use the ordinary emulated input ports.
-- Binary files are little endian unless their name says pixels (MAME native).
local m = type(manager.machine) == "function" and manager:machine() or manager.machine
local dir = assert(os.getenv("DUMP_DIR"), "DUMP_DIR required")
local game = os.getenv("CAPTURE_GAME") or "mystwarr"
assert(game == "mystwarr" or game == "gaiapols")
local sp = m.devices[":maincpu"].spaces["program"]
local zs = m.devices[":soundcpu"].spaces["program"]
local function item(dev, name, size, count)
    local id = assert(m.devices[dev].items["0/" .. name], dev .. "/" .. name)
    local it = emu.item(id)
    assert(it.size == size and it.count == count, "unexpected item shape: " .. name)
    return it
end
local plan = {
    {"k56_regs", item(":k056832", "m_regs", 2, 32)},
    {"k56_regsb", item(":k056832", "m_regsb", 2, 4)},
    {"k56_vram", item(":k056832", "m_videoram", 2, 69632)},
    {"k46_regs", item(":k055673", "m_kx46_regs", 1, 8)},
    {"k47_regs", item(":k055673", "m_kx47_regs", 2, 16)},
    {"k47_list", item(":k055673", "m_ram", 2, 2048)},
    {"k55_regs", item(":k055555", "m_regs", 1, 128)},
    {"k38_regs", item(":k054338", "m_regs", 2, 32)},
    {"k539_1_regs", item(":k054539_1", "regs", 1, 560)},
    {"k539_2_regs", item(":k054539_2", "regs", 1, 560)},
    {"k539_1_pos_latch", item(":k054539_1", "posreg_latch", 1, 24)},
    {"k539_2_pos_latch", item(":k054539_2", "posreg_latch", 1, 24)}
}
local function write_values(path, count, size, read)
    local out = assert(io.open(path, "wb"))
    local t = {}
    for i = 0, count - 1 do
        local v = read(i)
        for b = 0, size - 1 do t[#t + 1] = string.char((v >> (8 * b)) & 255) end
        if #t >= 8192 then out:write(table.concat(t)); t = {} end
    end
    out:write(table.concat(t)); out:close()
end
local log = assert(io.open(dir .. "/frames.txt", "w"))
local trace = assert(io.open(dir .. "/k539-writes.txt", "w"))
trace:write("# frame chip offset byte mask; original Z80 writes if Lua taps exist\n")
local want = {}
for f in (os.getenv("DUMPFRAMES") or "120,600,900"):gmatch("%d+") do want[tonumber(f)] = true end
local frame, captures, writes, active = 0, 0, 0, false
local coinframe = tonumber(os.getenv("COIN_FRAME") or (game == "gaiapols" and "1800" or "650"))
local startframe = tonumber(os.getenv("START_FRAME") or (game == "gaiapols" and "1850" or "700"))
_G.CAPTURE_KEEP = {}
local debugger = nil
if os.getenv("DEBUG_WRITE_TRACE") == "1" then
    debugger = type(m.debugger) == "function" and m:debugger() or m.debugger
    debugger:command("focus 1")
    debugger:command("observe 0")
    local ok, err = pcall(function() debugger.visible_cpu = m.devices[":soundcpu"] end)
    log:write("DEBUGGER visible_cpu setter " .. tostring(ok) .. " " .. tostring(err) .. "\n")
    debugger:command("temp0=0")
    for _, base in ipairs({0xe000, 0xe400}) do
        debugger:command(string.format('wpset %x,230,w,1,{logerror "K539_WRITE %%d %%04x %%02x\\n",temp0,wpaddr,wpdata; g}', base))
    end
    trace:write("# Full debugger watchpoint writes are in mame.log as K539_WRITE frame address byte.\n")
end
local tap_ok = pcall(function() return zs.install_write_tap end)
if tap_ok and zs.install_write_tap then
for chip, base in ipairs({0xe000, 0xe400}) do
    _G.CAPTURE_KEEP["tap" .. chip] = zs:install_write_tap(base, base + 0x22f, "capture_k539_" .. chip,
        function(off, data, mask)
            trace:write(string.format("%d %d %03x %02x %02x\n", frame, chip, off - base, data & 255, mask & 255))
            writes = writes + 1
        end)
end
else
    trace:write("# Lua install_write_tap unavailable in MAME 0.220.\n")
end
local memory = type(m.memory) == "function" and m:memory() or m.memory
local pcm = assert(memory.regions[":k054539"], "PCM region absent")
write_values(dir .. "/pcm-loaded.bin", pcm.size, 1, function(i) return pcm:read_u8(i) end)
local ports = type(m.ioport) == "function" and m:ioport().ports or m.ioport.ports
local function press(port, field, value)
    assert(ports[port].fields[field], port .. "/" .. field):set_value(value and 1 or 0)
end
local function dump(f, why)
    local prefix = string.format("%s/f%05d-", dir, f)
    for _, entry in ipairs(plan) do
        local it = entry[2]
        write_values(prefix .. entry[1] .. ".bin", it.count, it.size, function(i) return it:read(i) end)
    end
    local pal = game == "mystwarr" and 0x700000 or 0x420000
    write_values(prefix .. "palette.bin", 4096, 2, function(i) return sp:read_u16(pal + 2 * i) end)
    write_values(prefix .. "cpu-spriteram.bin", 32768, 2, function(i) return sp:read_u16(0x400000 + 2 * i) end)
    local pixels, w, h = m.screens[":screen"]:pixels()
    if not w then w, h = m.screens[":screen"]:width(), m.screens[":screen"]:height() end
    assert(type(pixels) == "string" and w and h, "screen pixels API unsupported")
    local out = assert(io.open(prefix .. "pixels-current.bin", "wb")); out:write(pixels); out:close()
    log:write(string.format("CAPTURE %d %s width=%d height=%d bytes=%d active=%02x,%02x pc=%x\n", f, why, w, h, #pixels,
        plan[9][2]:read(0x22c), plan[10][2]:read(0x22c), m.devices[":maincpu"].state["PC"].value))
    captures = captures + 1; log:flush(); trace:flush()
end
local function on_frame()
    frame = frame + 1
    if debugger then debugger:command("temp0=" .. string.format("%x", frame)) end
    -- Default schedule: attract capture before coin; later capture after start.
    if os.getenv("DRIVE_INPUTS") == "1" then
        local port = game == "mystwarr" and ":P1_P2" or ":IN0_P1"
        local coinport = game == "mystwarr" and ":IN0" or ":IN0_P1"
        press(coinport, "Coin 1", frame >= coinframe and frame < coinframe + 8)
        press(port, "1 Player Start", frame >= startframe and frame < startframe + 8)
        press(port, "P1 Button 1", frame > startframe + 60 and frame % 12 < 5)
        press(port, "P1 Right", frame > startframe + 60 and frame % 160 < 100)
    end
    local newactive = not active and ((plan[9][2]:read(0x22c) | plan[10][2]:read(0x22c)) ~= 0)
    if newactive then active = true end
    if want[frame] or newactive then dump(frame, newactive and "first-active-audio" or "requested") end
end
local function on_stop()
    log:write(string.format("END frames=%d captures=%d writes=%d active_seen=%s\n", frame, captures, writes, tostring(active)))
    log:close(); trace:close()
    print(string.format("CAPTURE_END frames=%d captures=%d writes=%d active=%s", frame, captures, writes, tostring(active)))
end
_G.CAPTURE_KEEP.frame = emu.register_frame(on_frame)
_G.CAPTURE_KEEP.stop = emu.register_stop(on_stop)
