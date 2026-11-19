-- Master Choke v2 (Permachoke Pasivo + ByxStorm Tirones en CL_Move) — Echidna (L4D2)
-- Toggle con la tecla 'C' (0x43) — Sin menu, directo
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_masterchoke_v2_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
    short GetAsyncKeyState(int vKey);
]])

local PAGE_EXECUTE_READWRITE = 0x40

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local TOGGLE_KEY = 0x43  -- Tecla 'C' (Toggle ON / OFF)
local CHOKE_VAL  = 90    -- Choke 1 (45) + Choke 2 (45) = 90 (Movimiento a tirones)

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
-- ESTADO Y VARIABLES
-- =========================================================================
local engine_base    = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))
local patch_addr     = nil
local orig_bytes_str = nil
local genuine_ack    = nil
local genuine_chok   = nil
local is_active      = false
local key_held       = false

local function log(msg)
    pcall(client.print, "[MasterChoke v2] " .. tostring(msg))
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
-- PARCHE NOP EN ENGINE.DLL
-- =========================================================================
local function apply_nop_patch()
    local addr = memory.find_pattern("engine.dll", NOP_PATTERN)
    if not addr or addr == 0 then return end

    patch_addr = addr
    orig_bytes_str = memory.read_bytes(addr, NOP_BYTES)

    local nops = string.char(0x90, 0x90, 0x90, 0x90)
    memory.patch(addr, nops)
    log(string.format("Parche NOP de motor activo @ 0x%X", addr))
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
-- TOGGLE CON LA TECLA 'C'
-- =========================================================================
function on_key_down(key)
    if key == TOGGLE_KEY and not key_held then
        key_held = true
        is_active = not is_active

        if is_active then
            log("BYXSTORM CHOKE ACTIVADO (Movimiento a tirones)")
        else
            local cs = get_client_state()
            if cs then write_int_safe(cs + CS_CHOKED_OFF, 0) end
            log("PASIVO FLUIDO (Solo Permachoke)")
        end
    end
end

function on_key_up(key)
    if key == TOGGLE_KEY then
        key_held = false
    end
end

-- =========================================================================
-- LOGICA EN ON_CL_MOVE_PRE (UBICACION EXACTA DE BYXSTORM)
-- =========================================================================
function on_cl_move_pre()
    if _G.echidna_masterchoke_v2_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    local cs = get_client_state()
    if not cs then return end

    local nc = get_netchannel(cs)
    if not nc then return end

    -- 1. Capturar red genuina (Single Owner)
    if not genuine_ack then
        local cur_ack = read_int(nc + NC_ACK_OFF)
        local cur_chk = read_int(nc + NC_CHOKED_OFF)
        if cur_ack and cur_ack ~= -1 then
            genuine_ack  = cur_ack
            genuine_chok = cur_chk or 0
        end
    end

    -- 2. Permachoke permanente en segundo plano (Socket protegido)
    write_int_safe(nc + NC_ACK_OFF, -1)
    write_int_safe(nc + NC_CHOKED_OFF, 255)

    -- 3. Inyeccion de ByxStorm en el momento previo al frame
    if is_active then
        -- Escribir 90 antes de que el motor empaquete el frame -> Produce los tirones
        write_int_safe(cs + CS_CHOKED_OFF, CHOKE_VAL)
    else
        -- 0 para caminar con total fluidez nativa
        write_int_safe(cs + CS_CHOKED_OFF, 0)
    end
end

-- =========================================================================
-- DESCARGA SEGURA
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
    is_active   = false
    log("Descargado y red restaurada limpiamente.")
end

log("Cargado — Permachoke pasivo activo. Presiona 'C' para alternar los tirones.")
