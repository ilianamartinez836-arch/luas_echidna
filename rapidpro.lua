-- Rapid Fire Server-Crusher (Cadencia Extrema + Saturacion de Red) — Echidna (L4D2)
-- Manten tu tecla de Rapid Fire para disparar a velocidad absurda y laguear el servidor
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_rapidcrusher_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
    short GetAsyncKeyState(int vKey);
]])

local PAGE_EXECUTE_READWRITE = 0x40

-- =========================================================================
-- CONFIGURACION DE DESTRUCCION
-- =========================================================================
local EXTRA_COMMANDS_BOOST = 2  -- Cantidad masiva de comandos por frame (Sube o baja segun tu PC)

local ENGINE_CS_OFF    = 4352236
local CS_NETCHAN_OFF   = 24
local CS_CHOKED_OFF    = 19024
local NC_ACK_OFF       = 16
local NC_CHOKED_OFF    = 28

local engine_base      = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))
local genuine_ack      = nil
local genuine_chok     = nil

local function log(msg)
    pcall(client.print, "[RapidCrusher] " .. tostring(msg))
end

local function read_int(addr)
    if not addr or addr < 0x10000 then return nil end
    local ok, val = pcall(function() return ffi.cast("int*", addr)[0] end)
    return ok and val or nil
end

local function write_int_safe(addr, val)
    if not addr or addr < 0x10000 then return false end
    local old_protect = ffi.new("unsigned long[1]")
    if ffi.C.VirtualProtect(ffi.cast("void*", addr), 4, PAGE_EXECUTE_READWRITE, old_protect) ~= 0 then
        local ok = pcall(function() ffi.cast("int*", addr)[0] = val end)
        ffi.C.VirtualProtect(ffi.cast("void*", addr), 4, old_protect[0], old_protect)
        return ok
    end
    return false
end

local function get_rapid_key()
    local ok, k = pcall(vars.get, "misc.rapid_key2")
    if ok and type(k) == "number" and k > 0 then return k end
    ok, k = pcall(vars.get, "misc.rapid_key")
    if ok and type(k) == "number" and k > 0 then return k end
    return 0x46 -- Tecla 'F' por defecto
end

local function get_netchannel()
    if not engine_base or engine_base == 0 then return nil end
    local cs = read_int(engine_base + ENGINE_CS_OFF)
    if not cs or cs == 0 then return nil end
    local nc = read_int(cs + CS_NETCHAN_OFF)
    if nc and nc > 0x10000 then return nc end
    return nil
end

-- =========================================================================
-- LOGICA CENTRAL EN CREATEMOVE
-- =========================================================================
function on_create_move(cmd, lp)
    if _G.echidna_rapidcrusher_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() or not lp or not lp:is_alive() then
        client.set_extra_commands(0)
        return
    end

    local key = get_rapid_key()
    local is_down = false
    pcall(function()
        if key > 0 then
            is_down = bit.band(ffi.C.GetAsyncKeyState(key), 0x8000) ~= 0
        end
    end)

    local nc = get_netchannel()

    if not is_down then
        client.set_extra_commands(0)
        if nc and genuine_ack and genuine_ack ~= -1 then
            write_int_safe(nc + NC_ACK_OFF, genuine_ack)
            if genuine_chok and genuine_chok ~= 255 then
                write_int_safe(nc + NC_CHOKED_OFF, genuine_chok)
            end
            genuine_ack = nil
        end
        return
    end

    -- 1. Capturar red genuina
    if nc and not genuine_ack then
        local cur_ack = read_int(nc + NC_ACK_OFF)
        local cur_chk = read_int(nc + NC_CHOKED_OFF)
        if cur_ack and cur_ack ~= -1 then
            genuine_ack  = cur_ack
            genuine_chok = cur_chk or 0
        end
    end

    -- 2. DISPARAR LA DESTRUCCION: Extra Commands Masivos + Spoof de Red
    client.set_extra_commands(EXTRA_COMMANDS_BOOST)

    if nc then
        write_int_safe(nc + NC_ACK_OFF, -1)
        write_int_safe(nc + NC_CHOKED_OFF, 255)
    end

    -- Forzar disparo continuo (IN_ATTACK)
    cmd:add_button(1)
end

function on_unload()
    client.set_extra_commands(0)
    local nc = get_netchannel()
    if nc and genuine_ack and genuine_ack ~= -1 then
        write_int_safe(nc + NC_ACK_OFF, genuine_ack)
    end
    log("Descargado y red restaurada.")
end

log("Cargado — Rapid Fire Server-Crusher listo. Manten tu tecla de Rapid Fire para saturar.")


