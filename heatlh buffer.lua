-- Godmode HealthBuffer Lock (Vida Temporal Permanente) — Echidna (L4D2)
-- Congela la vida de pildoras, adrenalina y revive para que NUNCA decaiga
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_healthbuffer_instance = INSTANCE

-- =========================================================================
-- 1. DESBLOQUEO Y ANULACION DE RATIO DE DECAIMIENTO POR CONVAR
-- =========================================================================
local FCVAR_CHEAT = 16384

local decay_cvars = {
    "pain_pills_decay_rate",
    "adrenaline_health_buffer"
}

for _, name in ipairs(decay_cvars) do
    local c = Cvars.FindVar(name)
    if c then
        pcall(c.RemoveFlags, c, FCVAR_CHEAT)
    end
end

local function enforce_decay_cvar()
    local c = Cvars.FindVar("pain_pills_decay_rate")
    if c then
        pcall(c.SetFloat, c, 0.0)
    end
end

-- =========================================================================
-- 2. BLOQUEO DE TIMESTAMP EN MEMORIA (CTERRORPLAYER)
-- =========================================================================
function on_create_move(cmd, lp)
    if _G.echidna_healthbuffer_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() or not lp or not lp:is_alive() then return end

    -- Solo para Supervivientes (Team 2)
    local team = lp:get_team()
    if team ~= 2 then return end

    -- Asegurar que la convar del juego este en 0
    enforce_decay_cvar()

    pcall(function()
        -- Leer vida temporal actual
        local buf = lp:get_prop_float("CTerrorPlayer", "m_healthBuffer") or 0.0

        -- Si tenemos vida temporal (por minima que sea), congelar el tiempo
        if buf > 0.1 then
            local curtime = GlobalVars.curtime() or 0.0
            
            -- Empujar el inicio del decaimiento 99999 segundos al futuro
            lp:set_prop_float("CTerrorPlayer", "m_healthBufferTime", curtime + 99999.0)
        end
    end)
end

function on_unload()
    local c = Cvars.FindVar("pain_pills_decay_rate")
    if c then
        pcall(c.SetFloat, c, 0.27) -- Valor original de Valve
    end
    client.print("[HealthBuffer] Descargado — Decaimiento normal restaurado.")
end

client.print("[HealthBuffer] Cargado — La vida de píldoras, adrenalina y revive ya NO decaerá.")
