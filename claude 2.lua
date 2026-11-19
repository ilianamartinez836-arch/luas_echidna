-- Choke Test (versión propia, mínima) — Echidna (L4D2)
-- Mantén la tecla para activar choke alto. Suelta para volver a pasivo (sin permachoke si lo desactivas).
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_choketest_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
]])

local CFG = {
    key       = 0x43,  -- 'C'
    turbo_val = 135,
}

local engine = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))
if not engine or engine == 0 then
    client.print("[ChokeTest] engine.dll no encontrado, abortando.")
    return
end

local function read_int(addr)
    if not addr or addr < 0x10000 then return nil end
    local ok, val = pcall(function() return ffi.cast("int*", addr)[0] end)
    return ok and val or nil
end

local function write_int_safe(addr, val)
    if not addr or addr < 0x10000 then return false end
    local old = ffi.new("unsigned long[1]")
    if ffi.C.VirtualProtect(ffi.cast("void*", addr), 4, 0x40, old) == 0 then return false end
    local ok = pcall(function() ffi.cast("int*", addr)[0] = val end)
    ffi.C.VirtualProtect(ffi.cast("void*", addr), 4, old[0], old)
    return ok
end

local function get_client_state()
    local cs = read_int(engine + 4352236)
    if cs and cs > 0x10000 then return cs end
    return nil
end

local function get_netchan(cs)
    local nc = read_int(cs + 24)
    if nc and nc > 0x10000 then return nc end
    return nil
end

-- Estado de dueño único del spoof: una sola captura, un solo restore.
local genuine_ack, genuine_choked = nil, nil
local active = false
local key_held = false

local function apply(now_active)
    local cs = get_client_state()
    if not cs then return end
    local nc = get_netchan(cs)

    if now_active then
        -- Capturar el ack/choked genuino UNA sola vez, antes de falsear nada.
        if nc and not genuine_ack then
            local cur_ack = read_int(nc + 16)
            local cur_chk = read_int(nc + 28)
            if cur_ack and cur_ack ~= -1 then
                genuine_ack = cur_ack
                genuine_choked = cur_chk or 0
            end
        end

        write_int_safe(cs + 19024, CFG.turbo_val)

        if nc then
            write_int_safe(nc + 16, -1)
            write_int_safe(nc + 28, 255)
        end
    else
        write_int_safe(cs + 19024, 0)

        if nc then
            -- Solo restaurar si el campo SIGUE siendo el que nosotros forzamos.
            -- Si cambió solo, el motor ya lo actualizó con algo genuino: no lo pisamos.
            local cur_ack = read_int(nc + 16)
            local cur_chk = read_int(nc + 28)

            if genuine_ack and cur_ack == -1 then
                write_int_safe(nc + 16, genuine_ack)
            end
            if genuine_choked and cur_chk == 255 then
                write_int_safe(nc + 28, genuine_choked)
            end
        end

        genuine_ack, genuine_choked = nil, nil
    end
end

function on_key_down(key)
    if key == CFG.key and not key_held then
        key_held = true
        active = true
    end
end

function on_key_up(key)
    if key == CFG.key then
        key_held = false
        active = false
    end
end

function on_create_move(cmd, lp)
    if _G.echidna_choketest_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end
    apply(active)
end

function on_unload()
    apply(false)
    client.print("[ChokeTest] Descargado — red restaurada.")
end

client.print(string.format("[ChokeTest] Cargado — mantén 'C' (turbo_val=%d). Sin NOP patch, sin HP buffer lock.", CFG.turbo_val))
