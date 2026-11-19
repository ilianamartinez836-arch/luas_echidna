-- Master Choke Unificado (Permachoke + Bleed + Choke 1&2 + NOP Patch) — Echidna (L4D2)
-- Pasivo: Permachoke continuo en segundo plano
-- Hold 'C': Desata la combinacion masiva (135 de choke en memoria)
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_masterchoke_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
    short GetAsyncKeyState(int vKey);
]])

local PAGE_EXECUTE_READWRITE = 0x40

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local VK_KEY_HOLD      = 0x43  -- Tecla 'C' (Virtual-Key 0x43)
local COMBO_TURBO_VAL  = 135   -- Suma de Bleed (45) + Choke1 (45) + Choke2 (45) = 135

-- =========================================================================
-- OFFSETS VERIFICADOS (Doc 04 & ByxStorm)
-- =========================================================================
local ENGINE_CS_OFF    = 4352236  -- *(engine_base + 4352236) = client_state crudo
local CS_NETCHAN_OFF   = 24       -- client_state + 24 = netchan
local CS_CHOKED_OFF    = 19024    -- client_state + 19024 = Choked_Commands
local NC_ACK_OFF       = 16       -- netchan + 16 = m_nOutSequenceNrAck
local NC_CHOKED_OFF    = 28       -- netchan + 28 = m_nChokedPackets

local NOP_PATTERN      = "85 C0 7E ?? 0F B6 C8"
local NOP_BYTES        = 4

-- =========================================================================
-- VARIABLES Y ESTADO
-- =========================================================================
local engine_base      = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))
local patch_addr       = nil
local orig_bytes_str   = nil
local genuine_ack      = nil
local genuine_chok     = nil
local was_holding_c    = false

local function log(msg)
    pcall(client.print, "[MasterChoke] " .. tostring(msg))
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
-- 1. APLICAR PARCHE NOP DE HEAVEN (DESBLOQUEO DE CANDADO DEL MOTOR)
-- =========================================================================
local function apply_nop_patch()
    local addr = memory.find_pattern("engine.dll", NOP_PATTERN)
    if not addr or addr == 0 then
        log("Aviso: Pattern NOP no encontrado en engine.dll.")
        return
    end

    patch_addr = addr
    orig_bytes_str = memory.read_bytes(addr, NOP_BYTES)

    local nops = string.char(0x90, 0x90, 0x90, 0x90)
    if memory.patch(addr, nops) then
        log(string.format("Parche NOP de motor activo @ 0x%X", addr))
    end
end

apply_nop_patch()

-- =========================================================================
-- RESOLUCION DE POINTERS
-- =========================================================================
local function get_client_state()
    if not engine_base or engine_base == 0 then return nil end
    local cs = read_int(engine_base + ENGINE_CS_OFF)
    if cs and cs > 0x10000 then return cs end
    return nil
end

local function get_netchannel(cs)
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

local function is_c_held()
    return bit.band(ffi.C.GetAsyncKeyState(VK_KEY_HOLD), 0x8000) ~= 0
end

-- =========================================================================
-- LOGICA EN CREATEMOVE (DOBLE MARCHA)
-- =========================================================================
function on_create_move(cmd, lp)
    if _G.echidna_masterchoke_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    local cs = get_client_state()
    if not cs then return end

    local nc = get_netchannel(cs)
    if not nc then return end

    -- 1. Capturar el estado genuino una sola vez para restauracion limpia
    if not genuine_ack then
        local cur_ack = read_int(nc + NC_ACK_OFF)
        local cur_chk = read_int(nc + NC_CHOKED_OFF)
        if cur_ack and cur_ack ~= -1 then
            genuine_ack  = cur_ack
            genuine_chok = cur_chk or 0
        end
    end

    -- 2. MARCHA 1 (SEGUNDO PLANO): Permachoke pasivo permanente
    write_int_safe(nc + NC_ACK_OFF, -1)
    write_int_safe(nc + NC_CHOKED_OFF, 255)

    -- 3. MARCHA 2 (TURBO): Al mantener presionada la tecla 'C'
    local holding_c = is_c_held()

    if holding_c then
        -- Desatar el combo completo (Bleed + Choke 1&2 apilados en 135)
        write_int_safe(cs + CS_CHOKED_OFF, COMBO_TURBO_VAL)
        was_holding_c = true
    else
        -- Al soltar la tecla 'C', limpiar el buffer a 0 y volver al Permachoke suave
        if was_holding_c then
            write_int_safe(cs + CS_CHOKED_OFF, 0)
            was_holding_c = false
        end
    end
end

-- =========================================================================
-- DESCARGA SEGURA (RESTAURACION LIMPIA DE MOTOR Y RED)
-- =========================================================================
function on_unload()
    -- 1. Restaurar bytes originales del motor
    if patch_addr and orig_bytes_str then
        pcall(memory.patch, patch_addr, orig_bytes_str)
        log("Parche NOP de motor revertido.")
    end

    local cs = get_client_state()
    if cs then
        -- 2. Resetear Choked_Commands a 0
        write_int_safe(cs + CS_CHOKED_OFF, 0)

        -- 3. Restaurar NetChannel a los valores reales
        local nc = get_netchannel(cs)
        if nc and genuine_ack and genuine_ack ~= -1 then
            write_int_safe(nc + NC_ACK_OFF, genuine_ack)
            if genuine_chok and genuine_chok ~= 255 then
                write_int_safe(nc + NC_CHOKED_OFF, genuine_chok)
            end
        end
    end

    patch_addr    = nil
    genuine_ack   = nil
    genuine_chok  = nil
    was_holding_c = false

    log("Descargado — Red y motor 100% restaurados.")
end

log("Cargado — Permachoke pasivo activo. Manten 'C' para desatar el combo (135).")
