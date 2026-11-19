-- =========================================================================
-- HVH NETWORK VAULT (PERMANENT PACKET BANK BOOSTER) — ECHIDNA (L4D2)
-- Complemento definitivo para el Rapid Fire privado nativo de Echidna
-- Toggle: Tecla 'G' (0x47) | Inmune a la muerte (Never Reset)
-- =========================================================================
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_hvh_vault_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
    short GetAsyncKeyState(int vKey);
]])

local PAGE_EXECUTE_READWRITE = 0x40

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local TOGGLE_KEY  = 0x47  -- Tecla 'G' (Toggle ON / OFF)
local CHOKE_BOOST = 135   -- Inyeccion masiva para empaquetado de red

-- =========================================================================
-- OFFSETS VERIFICADOS
-- =========================================================================
local ENGINE_CS_OFF = 4352236  -- *(engine_base + 4352236) = raw client_state
local CS_NETCHAN_OFF= 24       -- client_state + 24 = netchan
local CS_CHOKED_OFF = 19024    -- client_state + 19024 = Choked_Commands
local NC_ACK_OFF    = 16       -- netchan + 16 = m_nOutSequenceNrAck
local NC_CHOKED_OFF = 28       -- netchan + 28 = m_nChokedPackets

local NOP_PATTERN   = "85 C0 7E ?? 0F B6 C8"
local NOP_BYTES     = 4

-- =========================================================================
-- ESTADO INTERNO (INMUNE A MUERTE / RESETS)
-- =========================================================================
local engine_base    = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))
local patch_addr     = nil
local orig_bytes_str = nil
local genuine_ack    = nil
local genuine_chok   = nil
local is_boost_on    = true   -- Activo por defecto al inyectar
local key_held       = false

local function log(msg)
    pcall(client.print, "[HvHVault] " .. tostring(msg))
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
-- PARCHE NOP DE HEAVEN (DESBLOQUEO PERMANENTE DEL MOTOR)
-- =========================================================================
local function apply_nop_patch()
    local addr = memory.find_pattern("engine.dll", NOP_PATTERN)
    if not addr or addr == 0 then return end

    patch_addr = addr
    orig_bytes_str = memory.read_bytes(addr, NOP_BYTES)

    local nops = string.char(0x90, 0x90, 0x90, 0x90)
    memory.patch(addr, nops)
    log(string.format("Parche NOP activo @ 0x%X", addr))
end

apply_nop_patch()

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

-- =========================================================================
-- TOGGLE CON LA TECLA 'G'
-- =========================================================================
function on_key_down(key)
    if key == TOGGLE_KEY and not key_held then
        key_held = true
        is_boost_on = not is_boost_on

        if is_boost_on then
            log("BOOST DE RED ACTIVADO (135 Choke)")
        else
            local cs = get_client_state()
            if cs then write_int_safe(cs + CS_CHOKED_OFF, 0) end
            log("BOOST EN PAUSA (Permachoke pasivo sigue activo de fondo)")
        end
    end
end

function on_key_up(key)
    if key == TOGGLE_KEY then
        key_held = false
    end
end

-- =========================================================================
-- BLOQUEO DE DECAIMIENTO DE VIDA TEMPORAL (GODMODE BUFFER)
-- =========================================================================
local function lock_health_buffer()
    local ok, lp = pcall(EntityCache.GetLocal)
    if not ok or not lp then return end

    pcall(function()
        local buf = lp:get_prop_float("CTerrorPlayer", "m_healthBuffer") or 0.0
        if buf > 0.1 then
            local cur_time = GlobalVars.curtime() or 0.0
            lp:set_prop_float("CTerrorPlayer", "m_healthBufferTime", cur_time + 99999.0)
        end
    end)
end

-- =========================================================================
-- MOTOR DE RED CENTRAL (CORRE EN CADA TICK SIN IMPORTAR SI ESTAS VIVO/MUERTO)
-- =========================================================================
function on_cl_move_pre()
    if _G.echidna_hvh_vault_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    local cs = get_client_state()
    if not cs then return end

    local nc = get_netchannel(cs)
    if not nc then return end

    -- 1. Capturar valores reales una sola vez al entrar
    if not genuine_ack then
        local cur_ack = read_int(nc + NC_ACK_OFF)
        local cur_chk = read_int(nc + NC_CHOKED_OFF)
        if cur_ack and cur_ack ~= -1 then
            genuine_ack  = cur_ack
            genuine_chok = cur_chk or 0
        end
    end

    -- 2. EL BANCO ETERNO (PERMACHOKE PASIVO PERMANENTE)
    -- NUNCA se resetea aunque mueras, caigas o estes de espectador
    write_int_safe(nc + NC_ACK_OFF, -1)
    write_int_safe(nc + NC_CHOKED_OFF, 255)

    -- 3. INYECCION DE CHOKE AMPLIFICADOR
    if is_boost_on then
        write_int_safe(cs + CS_CHOKED_OFF, CHOKE_BOOST)
    else
        write_int_safe(cs + CS_CHOKED_OFF, 0)
    end
end

function on_create_move(cmd, lp)
    if _G.echidna_hvh_vault_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    -- Congelar vida temporal en cada frame si tenemos vida acumulada
    lock_health_buffer()
end

-- =========================================================================
-- DESCARGA SEGURA (RESTAURACION LIMPIA SOLO AL DESCARGAR EL SCRIPT)
-- =========================================================================
function on_unload()
    if patch_addr and orig_bytes_str then
        pcall(memory.patch, patch_addr, orig_bytes_str)
    end

    local cs = get_client_state()
    if cs then
        write_int_safe(cs + CS_CHOKED_OFF, 0)
        local nc = get_netchannel(cs)
        if nc and genuine_ack and genuine_ack ~= -1 then
            write_int_safe(nc + NC_ACK_OFF, genuine_ack)
            if genuine_chok and genuine_chok ~= 255 then
                write_int_safe(nc + NC_CHOKED_OFF, genuine_chok)
            end
        end
    end

    patch_addr  = nil
    genuine_ack = nil
    is_boost_on = false
    log("Descargado — Red del motor restaurada.")
end

log("Cargado — HvH Vault Activo (Inmune a muerte / Toggle 'G').")
