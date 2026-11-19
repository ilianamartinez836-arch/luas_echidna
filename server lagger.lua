-- Server Lagger Limpio (Command Flooding & Physics Overload) — Echidna (L4D2)
-- Manten 'V' para ahogar el servidor sin pantallas negras ni errores de paquete
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_serverlag_clean_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
    short GetAsyncKeyState(int vKey);
]])

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local VK_KEY_HOLD     = 0x56  -- Tecla 'V' (Manten para laguear)
local EXTRA_CMDS_MAX  = 14    -- 14 comandos extra por tick (techo maximo de Source)
local SEQ_PULSE_STEP  = 2500  -- Desfase de secuencia periodico

-- =========================================================================
-- PARCHE NOP EN ENGINE.DLL (DESBLOQUEO DE LIMITES DE SALIDA)
-- =========================================================================
local NOP_PATTERN    = "85 C0 7E ?? 0F B6 C8"
local patch_addr     = nil
local orig_bytes_str = nil

local function apply_nop_patch()
    local addr = memory.find_pattern("engine.dll", NOP_PATTERN)
    if not addr or addr == 0 then return end

    patch_addr = addr
    orig_bytes_str = memory.read_bytes(addr, 4)

    local nops = string.char(0x90, 0x90, 0x90, 0x90)
    memory.patch(addr, nops)
    pcall(client.print, string.format("[ServerLagger] Parche NOP activo @ 0x%X", addr))
end

apply_nop_patch()

-- =========================================================================
-- ESTADO Y CONTROL
-- =========================================================================
local was_holding = false
local pulse_tick  = 0

local function is_key_held()
    return bit.band(ffi.C.GetAsyncKeyState(VK_KEY_HOLD), 0x8000) ~= 0
end

-- =========================================================================
-- INYECCION EN CL_MOVE PRE (SATURACION DE COMANDOS REALES)
-- =========================================================================
function on_cl_move_pre()
    if _G.echidna_serverlag_clean_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then
        client.set_extra_commands(0)
        return
    end

    local holding = is_key_held()

    if holding then
        -- 1. Forzar 14 comandos de fisicas reales por tick al servidor
        client.set_extra_commands(EXTRA_CMDS_MAX)

        -- 2. Cada 5 ticks, inyectar un pulso de secuencia para forzar recalculo de lag
        pulse_tick = pulse_tick + 1
        if pulse_tick % 5 == 0 then
            local nc = EngineClient.GetNetChannelInfo()
            if nc and not nc:IsNull() then
                local cur_seq = nc:m_nOutSequenceNr()
                if cur_seq then
                    nc:SetOutSequenceNr(cur_seq + SEQ_PULSE_STEP)
                end
            end
        end

        was_holding = true
    else
        -- Al soltar la V: devolver comandos extra a 0 de inmediato
        if was_holding then
            client.set_extra_commands(0)
            pulse_tick  = 0
            was_holding = false
        end
    end
end

-- =========================================================================
-- DESCARGA LIMPIA
-- =========================================================================
function on_unload()
    client.set_extra_commands(0)

    if patch_addr and orig_bytes_str then
        pcall(memory.patch, patch_addr, orig_bytes_str)
    end

    patch_addr  = nil
    was_holding = false
    client.print("[ServerLagger] Descargado — Servidor y cliente normalizados.")
end

client.print("[ServerLagger] Cargado — Manten 'V' para saturar el servidor de fisicas.")
