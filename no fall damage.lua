-- No Fall Damage (Sequence Shift Exploit +90000) — Echidna (L4D2)
-- Solo activo para Supervivientes (Team 2), desactivado en Infectados
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_nofall_shift_instance = INSTANCE

local SHIFT_AMOUNT = 90000
local FALL_THRESHOLD = 560.0

-- =========================================================================
-- EJECUTAR SEQUENCE SHIFT MASIVO (+90000)
-- =========================================================================
local function execute_sequence_shift()
    -- 1. Intentar por INetChannel nativo de Echidna
    local nc = EngineClient.GetNetChannelInfo()
    if nc and not nc:IsNull() then
        local cur = nc:m_nOutSequenceNr()
        if cur then
            nc:SetOutSequenceNr(cur + SHIFT_AMOUNT)
            return
        end
    end

    -- 2. Respaldo por punteros crudos (mismo metodo de Aimware)
    local eng = memory.get_module_base("engine.dll")
    if eng and eng > 0 then
        local cs = memory.read_i32(eng + 4352236)
        if cs and cs > 0x10000 then
            local p_nc = memory.read_i32(cs + 24)
            if p_nc and p_nc > 0x10000 then
                local cur_seq = memory.read_i32(p_nc + 8)
                if cur_seq then
                    memory.write_i32(p_nc + 8, cur_seq + SHIFT_AMOUNT)
                end
            end
        end
    end
end

-- =========================================================================
-- LOGICA EN CREATEMOVE
-- =========================================================================
function on_create_move(cmd, lp)
    if _G.echidna_nofall_shift_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() or not lp or not lp:is_alive() then return end

    -- FILTRO DE EQUIPO:
    -- Team 2 = Survivor (Activo)
    -- Team 3 = Infected (Desactivado)
    local team = lp:get_team()
    if team ~= 2 then return end

    -- Obtener fall velocity actual
    local fall_vel = 0
    if lp.GetFallVelocity then
        fall_vel = lp:GetFallVelocity() or 0
    end
    if fall_vel <= 0 then
        pcall(function()
            fall_vel = lp:get_prop_float("CBasePlayer", "m_flFallVelocity") or 0
        end)
    end

    -- Respaldo de velocidad vertical de caida (por si la netvar tiene retraso)
    local vel = lp:get_velocity()
    local is_falling_fast = (fall_vel > FALL_THRESHOLD) or (vel and vel.z and vel.z < -FALL_THRESHOLD)

    -- Si estamos en caida letal -> Disparar el exploit de secuencia
    if is_falling_fast then
        execute_sequence_shift()
    end
end

function on_unload()
    client.print("[NoFallDamage] Descargado.")
end

client.print("[NoFallDamage] Cargado — Activo solo en Supervivientes (+90000 Shift).")

