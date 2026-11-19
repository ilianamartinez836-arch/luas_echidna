-- FakeLag CL_Move Pre — Echidna (L4D2)
-- Sigue la arquitectura de 5 pasos con set_send_packet y netchan 0xB8
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_fakelag_pre_instance = INSTANCE

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local TOGGLE_KEY   = 0x4A  -- Tecla 'J'
local CHOKE_AMOUNT = 14    -- Cantidad de ticks a retener (1 a 14)

-- =========================================================================
-- RESOLUCION DE PUNTERO A NETCHAN (PUNTO 4)
-- =========================================================================
local function get_netchan_ptr()
    -- 1. engine_base + 4352236 -> client_state -> client_state + 24 -> netchan
    local eng = memory.get_module_base("engine.dll")
    if eng and eng > 0 then
        local cs = memory.read_i32(eng + 4352236)
        if cs and cs > 0x10000 then
            local nc = memory.read_i32(cs + 24)
            if nc and nc > 0x10000 then
                return nc
            end
        end
    end

    -- 2. Fallback nativo
    local nc_info = EngineClient.GetNetChannelInfo()
    if nc_info and not nc_info:IsNull() then
        local ptr = nc_info:GetPtr()
        if ptr then
            local uptr = tonumber(ffi.cast("uintptr_t", ptr))
            if uptr and uptr > 0x10000 then
                return uptr
            end
        end
    end

    return nil
end

-- =========================================================================
-- ESTADO
-- =========================================================================
local active   = false
local key_held = false
local counter  = 0

local function log(msg)
    pcall(client.print, "[FakeLag] " .. tostring(msg))
end

-- =========================================================================
-- TOGGLE CON TECLA 'J'
-- =========================================================================
function on_key_down(key)
    if key == TOGGLE_KEY and not key_held then
        key_held = true
        active = not active
        counter = 0

        -- Al desactivar, restaurar netchan inmediatamente
        if not active then
            local nc = get_netchan_ptr()
            if nc then
                pcall(memory.write_f32, nc + 0xB8, 0.0)
                pcall(memory.write_f64, nc + 0xB8, 0.0)
            end
            pcall(client.set_send_packet, true)
            log("DESACTIVADO")
        else
            log("ACTIVADO (Choke: " .. tostring(CHOKE_AMOUNT) .. ")")
        end
    end
end

function on_key_up(key)
    if key == TOGGLE_KEY then
        key_held = false
    end
end

-- =========================================================================
-- LOGICA CENTRAL EN ON_CL_MOVE_PRE (PUNTOS 1, 2, 3 Y 5)
-- =========================================================================
function on_cl_move_pre()
    if _G.echidna_fakelag_pre_instance ~= INSTANCE then return end

    if not active or not EngineClient.IsInGame() then
        if counter > 0 then
            local nc = get_netchan_ptr()
            if nc then
                pcall(memory.write_f32, nc + 0xB8, 0.0)
                pcall(memory.write_f64, nc + 0xB8, 0.0)
            end
            pcall(client.set_send_packet, true)
            counter = 0
        end
        return
    end

    local nc = get_netchan_ptr()
    if not nc then return end

    local amount = math.max(1, math.min(14, CHOKE_AMOUNT))

    if counter < amount then
        -- 1. Retener el paquete
        pcall(client.set_send_packet, false)

        -- 3. Bloquear netchan (cleartime = 999999.0)
        pcall(memory.write_f32, nc + 0xB8, 999999.0)
        pcall(memory.write_f64, nc + 0xB8, 999999.0)

        counter = counter + 1
    else
        -- Liberar el paquete y enviar la ráfaga
        pcall(client.set_send_packet, true)

        -- Restaurar netchan (cleartime = 0.0)
        pcall(memory.write_f32, nc + 0xB8, 0.0)
        pcall(memory.write_f64, nc + 0xB8, 0.0)

        counter = 0
    end
end

-- =========================================================================
-- DESCARGA
-- =========================================================================
function on_unload()
    local nc = get_netchan_ptr()
    if nc then
        pcall(memory.write_f32, nc + 0xB8, 0.0)
        pcall(memory.write_f64, nc + 0xB8, 0.0)
    end
    pcall(client.set_send_packet, true)
    active = false
    counter = 0
    log("Descargado.")
end

log("Cargado — Presiona 'J' para activar/desactivar.")
