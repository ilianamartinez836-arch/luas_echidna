-- No ViewShake / No PunchAngle (Echidna L4D2)
-- Elimina el temblor de camara por rocas del Tank, pisadas y golpes
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_noshake_instance = INSTANCE

local ZERO_VEC = { x = 0, y = 0, z = 0 }

function on_create_move(cmd, lp)
    if _G.echidna_noshake_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() or not lp then return end

    -- 1. Limpiar PunchAngle (Offset 0x1204) y PunchAngleVel (0x1210)
    pcall(lp.set_prop_vector, lp, "CBasePlayer", "m_vecPunchAngle", ZERO_VEC)
    pcall(lp.set_prop_vector, lp, "CBasePlayer", "m_vecPunchAngleVel", ZERO_VEC)

    -- 2. Limpiar Roll (inclinacion de camara por sacudidas)
    local ang = cmd:get_viewangles()
    if ang then
        local z = ang.z or ang[3] or ang.roll or 0
        if z ~= 0 then
            cmd:set_viewangles(ang.x or ang[1], ang.y or ang[2], 0)
        end
    end
end

-- Congelar los angulos de vista para que el render no tiemble
function on_override_view(ox, oy, oz, ax, ay, az, fov)
    if not EngineClient.IsInGame() then return end
    local lp = EntityCache.GetLocal()
    if lp then
        pcall(lp.set_prop_vector, lp, "CBasePlayer", "m_vecPunchAngle", ZERO_VEC)
        pcall(lp.set_prop_vector, lp, "CBasePlayer", "m_vecPunchAngleVel", ZERO_VEC)
    end
end

client.print("[NoShake] Activo: camara estabilizada (Punch & Shake anulados).")

function on_unload()
    client.print("[NoShake] Descargado.")
end
