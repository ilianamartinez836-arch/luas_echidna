-- No Tank Rock Shake / No ViewPunch — Echidna (L4D2)
-- Elimina por completo la sacudida de camara por impacto de rocas y golpes del Tank
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_norockshake_instance = INSTANCE

local ZERO_VEC = { x = 0.0, y = 0.0, z = 0.0 }

-- Desactivar el hook interno de calculo de vista para evitar sacudidas calculadas por el motor
pcall(function()
    if echidna_hooks and echidna_hooks.exists("BasePlayer_CalcPlayerView") then
        echidna_hooks.disable("BasePlayer_CalcPlayerView")
    end
end)

local function clean_punch_angles(lp)
    if not lp then return end
    pcall(lp.set_prop_vector, lp, "CBasePlayer", "m_vecPunchAngle", ZERO_VEC)
    pcall(lp.set_prop_vector, lp, "CBasePlayer", "m_vecPunchAngleVel", ZERO_VEC)
    pcall(lp.set_prop_vector, lp, "CTerrorPlayer", "m_vecPunchAngle", ZERO_VEC)
    pcall(lp.set_prop_vector, lp, "CTerrorPlayer", "m_vecPunchAngleVel", ZERO_VEC)
end

function on_create_move(cmd, lp)
    if _G.echidna_norockshake_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() or not lp or not lp:is_alive() then return end

    -- 1. Limpiar PunchAngle y su velocidad angular
    clean_punch_angles(lp)

    -- 2. Eliminar el roll (balanceo lateral de la camara)
    local ang = cmd:get_viewangles()
    if ang then
        local roll = ang.z or ang[3] or ang.roll or 0.0
        if math.abs(roll) > 0.01 then
            cmd:set_viewangles(ang.x or ang[1], ang.y or ang[2], 0.0)
        end
    end
end

-- Limpieza continua durante el renderizado de la camara
function on_override_view(ox, oy, oz, ax, ay, az, fov)
    if not EngineClient.IsInGame() then return end
    local lp = EntityCache.GetLocal()
    if lp and lp:is_alive() then
        clean_punch_angles(lp)
    end
end

function on_unload()
    -- Restaurar el hook del motor al descargar
    pcall(function()
        if echidna_hooks and echidna_hooks.exists("BasePlayer_CalcPlayerView") then
            echidna_hooks.enable("BasePlayer_CalcPlayerView")
        end
    end)
    client.print("[NoRockShake] Descargado.")
end

client.print("[NoRockShake] Cargado — Camara fija contra impactos de roca y golpes.")
