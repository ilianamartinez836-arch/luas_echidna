-- Auto No Hang / Anti-Incap Exploit — Echidna (L4D2)
-- Desincronizacion de secuencias de red al quedar colgado o incapacitado

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local ENABLED         = true   -- Activar/desactivar exploit directamente
local SEQ_STEP_AMOUNT = 10000  -- Desfase de secuencias por tick (10000)

-- =========================================================================
-- LOGICA EN CREATEMOVE
-- =========================================================================
function on_create_move(cmd, lp)
    if not ENABLED then return end
    if not lp or not lp:is_alive() then return end
    if not EngineClient.IsInGame() then return end

    -- Comprobar si estamos colgados de un borde o incapacitados
    local is_hanging = false
    local is_incap   = false

    pcall(function()
        is_hanging = (lp.is_hanging_from_ledge and lp:is_hanging_from_ledge()) 
                  or (lp:get_prop_int("CTerrorPlayer", "m_isHangingFromLedge") == 1)

        is_incap   = (lp.is_incapacitated and lp:is_incapacitated()) 
                  or (lp:get_prop_int("CTerrorPlayer", "m_isIncapacitated") == 1)
    end)

    -- Si estamos en estado de hang o incap -> desfasar secuencia saliente
    if is_hanging then
        local nc = EngineClient.GetNetChannelInfo()
        if nc and not nc:IsNull() then
            local cur_seq = nc:m_nOutSequenceNr()
            if cur_seq then
                nc:SetOutSequenceNr(cur_seq + SEQ_STEP_AMOUNT)
            end
        end
    end
end

function on_unload()
    client.print("[NoHang] Descargado.")
end

client.print("[NoHang/AntiIncap] Cargado — Activo directamente.")


