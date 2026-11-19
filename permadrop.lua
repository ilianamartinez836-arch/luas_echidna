-- Permadrop (Packet Drop Spoofing / Zero-Choke Desync) — Echidna (L4D2)
-- Desync de red mediante perdida de paquetes simulada (100% fluido, sin tirones)
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_permadrop_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
]])

local PAGE_EXECUTE_READWRITE = 0x40

-- =========================================================================
-- OFFSETS VERIFICADOS EN INETCHANNEL
-- =========================================================================
local ENGINE_CS_OFF     = 4352236  -- *(engine_base + 4352236) = raw client_state
local CS_NETCHAN_OFF    = 24       -- client_state + 24 = netchan
local NC_PACKETDROP_OFF = 32       -- netchan + 32 = m_PacketDrop (inmediatamente tras chokedpackets +28)

local engine_base       = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))
local genuine_drop      = nil

local function log(msg)
    pcall(client.print, "[Permadrop] " .. tostring(msg))
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

-- =========================================================================
-- RESOLUCION DE NETCHANNEL
-- =========================================================================
local function get_netchannel()
    if not engine_base or engine_base == 0 then return nil end
    local cs = read_int(engine_base + ENGINE_CS_OFF)
    if not cs or cs == 0 then return nil end
    local nc = read_int(cs + CS_NETCHAN_OFF)
    if nc and nc > 0x10000 then return nc end

    local nc_info = EngineClient.GetNetChannelInfo()
    if nc_info and not nc_info:IsNull() then
        local ptr = nc_info:GetPtr()
        if ptr then
            local uptr = tonumber(ffi.cast("uintptr_t", ptr))
            if uptr and uptr > 0x10000 then return uptr end
        end
    end
    return nil
end

-- =========================================================================
-- LOGICA EN CREATEMOVE (SPOOF DE PACKET DROP CONSTANTE)
-- =========================================================================
function on_create_move(cmd, lp)
    if _G.echidna_permadrop_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    local nc = get_netchannel()
    if not nc then return end

    -- Capturar el valor real una sola vez para restauracion limpia
    if not genuine_drop then
        local cur_drop = read_int(nc + NC_PACKETDROP_OFF)
        if cur_drop and cur_drop ~= 255 then
            genuine_drop = cur_drop
        end
    end

    -- Forzar Packet Drop continuo en el socket (Simula perdida masiva sin retener comandos)
    write_int_safe(nc + NC_PACKETDROP_OFF, 255)
end

-- =========================================================================
-- DESCARGA SEGURA
-- =========================================================================
function on_unload()
    local nc = get_netchannel()
    if nc and genuine_drop and genuine_drop ~= 255 then
        write_int_safe(nc + NC_PACKETDROP_OFF, genuine_drop)
    end
    genuine_drop = nil
    log("Descargado — Packet Drop restaurado a la normalidad.")
end

log("Cargado — Permadrop activo permanentemente (Desync fluido sin tirones).")
