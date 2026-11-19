-- Server Lag Overload / HvH Disruptor — Echidna (L4D2)
-- Toggle con la tecla 'H' (0x48) — Sin menu, directo
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_server_overload_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
    short GetAsyncKeyState(int vKey);
]])

local PAGE_EXECUTE_READWRITE = 0x40

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local TOGGLE_KEY = 0x48  -- Tecla 'H' (Toggle ON / OFF)
local EXTRA_CMDS = 14    -- 14 comandos extra por tick (Saturacion de fisicas)
local CHOKE_BIAS = 90    -- Choke inflado para saturar Lag Compensation

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
-- ESTADO
-- =========================================================================
local engine_base    = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))
local patch_addr     = nil
local orig_bytes_str = nil
local genuine_ack    = nil
local genuine_chok   = nil
local active         = false
local key_held       = false

local function log(msg)
    pcall(client.print, "[ServerOverload] " .. tostring(msg))
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
-- PARCHE NOP EN ENGINE.DLL (DESBLOQUEO DE LIMITES)
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
-- TOGGLE CON LA TECLA 'H'
-- =========================================================================
function on_key_down(key)
    if key == TOGGLE_KEY and not key_held then
        key_held = true
        active = not active

        if active then
            log("SERVER OVERLOAD ACTIVADO (Lagueando servidor)")
        else
            client.set_extra_commands(0)
            local cs = get_client_state()
            if cs then write_int_safe(cs + CS_CHOKED_OFF, 0) end
            log("SERVER OVERLOAD DESACTIVADO")
        end
    end
end

function on_key_up(key)
    if key == TOGGLE_KEY then
        key_held = false
    end
end

-- =========================================================================
-- INYECCION DE SATURACION EN CL_MOVE PRE
-- =========================================================================
function on_cl_move_pre()
    if _G.echidna_server_overload_instance ~= INSTANCE then return end
    if not active or not EngineClient.IsInGame() then
        client.set_extra_commands(0)
        return
    end

    local cs = get_client_state()
    if not cs then return end

    local nc = get_netchannel(cs)
    if not nc then return end

    -- Capturar red genuina (Single Owner)
    if not genuine_ack then
        local cur_ack = read_int(nc + NC_ACK_OFF)
        local cur_chk = read_int(nc + NC_CHOKED_OFF)
        if cur_ack and cur_ack ~= -1 then
            genuine_ack  = cur_ack
            genuine_chok = cur_chk or 0
        end
    end

    -- 1. Inyectar 14 llamadas extra por tick (Saturacion de CPU en el servidor)
    client.set_extra_commands(EXTRA_CMDS)

    -- 2. Spoofear NetChannel
    write_int_safe(nc + NC_ACK_OFF, -1)
    write_int_safe(nc + NC_CHOKED_OFF, 255)

    -- 3. Inflar Choked_Commands en memoria para sobrecargar el Lag Compensation
    write_int_safe(cs + CS_CHOKED_OFF, CHOKE_BIAS)
end

-- =========================================================================
-- DESCARGA LIMPIA
-- =========================================================================
function on_unload()
    active = false
    client.set_extra_commands(0)

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
    log("Descargado — Servidor y red restaurados.")
end

log("Cargado — Presiona 'H' para alternar la sobrecarga del servidor.")
