-- =========================================================================
-- BYXSTORM HYPER-STRAFE & BHOP V3 (DEFINITIVE EDITION) — ECHIDNA (L4D2)
-- Features: Micro-Tick Ground Injection + Prediction Lookahead + Step-Fix
-- =========================================================================
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_byx_v3_instance = INSTANCE

pcall(ffi.cdef, [[
    short GetAsyncKeyState(int vKey);
]])

-- =========================================================================
-- CONFIGURACION (MODIFICA A TU GUSTO AQUI)
-- =========================================================================
local BOOST_TICKS_AMOUNT   = 4     -- Ticks extra inyectados en el despegue (3 a 6 es el rango letal)
local KEY_SPACE            = 0x20   -- Tecla Espacio
local MAX_AIR_ACCEL        = 1500.0 -- Aceleracion aerea maxima agresiva

-- =========================================================================
-- CONSTANTES Y HELPERS
-- =========================================================================
local IN_JUMP     = 2
local DEG2RAD     = 0.01745329251
local RAD2DEG     = 57.295779513

local last_yaw      = 0.0
local just_jumped   = false
local was_on_ground = true

local function is_space_down()
    return bit.band(ffi.C.GetAsyncKeyState(KEY_SPACE), 0x8000) ~= 0
end

local function angle_normalize(a)
    while a > 180.0 do a = a - 360.0 end
    while a < -180.0 do a = a + 360.0 end
    return a
end

-- =========================================================================
-- 2. LOGICA EN CREATEMOVE (BHOP CERO FRICCION + STRAFE PREDICHO)
-- =========================================================================
function on_create_move(cmd, lp)
    if _G.echidna_byx_v3_instance ~= INSTANCE then return end
    if not cmd or not lp or not lp:is_alive() or not EngineClient.IsInGame() then return end

    -- Filtro de escaleras de mano (Ladder) y Noclip
    local movetype = 0
    pcall(function() movetype = lp:get_prop_int("CTerrorPlayer", "movetype") or 0 end)
    if movetype == 8 or movetype == 9 then return end

    -- Deteccion de suelo nativa de ByxStorm (m_hGroundEntity)
    local on_ground = false
    pcall(function()
        local h_ground = lp:get_prop_int("CBasePlayer", "m_hGroundEntity")
        if h_ground and h_ground ~= -1 and h_ground ~= 0xFFFFFFFF and h_ground ~= 2047 then
            on_ground = true
        else
            on_ground = lp:is_on_ground()
        end
    end)

    local space_held = is_space_down()

    if not space_held then
        was_on_ground = on_ground
        just_jumped   = false
        local va = cmd:get_viewangles()
        if va then last_yaw = va.y or va[2] or 0.0 end
        return
    end

    -- A) BUNNYHOP CERO FRICCION (FRAME 0)
    if on_ground then
        cmd:add_button(IN_JUMP)

        -- Si veniamos del aire y tocamos suelo -> disparar flag de salto largo
        if not was_on_ground then
            just_jumped = true
        end

        -- Impulso diagonal inicial si arrancamos desde cero
        local cur_fm = cmd:get_forwardmove() or 0.0
        local cur_sm = cmd:get_sidemove() or 0.0
        if math.abs(cur_fm) < 10.0 and math.abs(cur_sm) < 10.0 then
            cmd:set_forwardmove(450.0)
            cmd:set_sidemove(450.0)
        end
    else
        cmd:remove_button(IN_JUMP)
    end

    -- B) AUTO-STRAFER CON PREDICCION ADELANTADA (EN EL AIRE)
    if not on_ground then
        local vel = lp:get_velocity()
        if vel and vel.x then
            -- PREDICCION DEL SIGUIENTE TICK: calcular aceleracion futura
            local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y)

            -- STEP-FIX: Resbalar sobre peldaños y desniveles sin perder velocidad
            if vel.z and vel.z < 0 and vel.z > -160.0 then
                cmd:set_upmove(250.0)
            end

            if speed > 1.5 then
                local maxSpeed  = 1000.0
                local airAccel  = MAX_AIR_ACCEL
                local wishSpeed = 1000.0

                -- Formula matematica Perfect Delta con aceleracion reforzada
                local term = (wishSpeed / airAccel) / maxSpeed * 400.0 / speed
                local view = cmd:get_viewangles()
                local cur_yaw = view and (view.y or view[2] or 0.0) or 0.0
                local yawRad = cur_yaw * DEG2RAD
                local velDir = math.atan2(vel.y, vel.x) - yawRad

                local cur_sm = cmd:get_sidemove() or 0.0
                local cur_fm = cmd:get_forwardmove() or 0.0
                local wishAng = math.atan2(-cur_sm, cur_fm)

                -- FAILSAFE DE GIRO VIOLENTO: Si giras muy rapido, no se apaga
                if term <= -1.0 or term >= 1.0 then
                    local m_dx = cmd:get_mousedx() or 0
                    local yaw_delta = angle_normalize(cur_yaw - last_yaw)

                    if m_dx < 0 or yaw_delta > 0.01 then
                        cmd:set_sidemove(-450.0)
                    elseif m_dx > 0 or yaw_delta < -0.01 then
                        cmd:set_sidemove(450.0)
                    end
                else
                    local perfectDelta = math.acos(term)
                    local delta = angle_normalize((velDir - wishAng) * RAD2DEG)
                    local moveDir = (delta < 0.0) and (velDir + perfectDelta) or (velDir - perfectDelta)

                    cmd:set_forwardmove(math.cos(moveDir) * 450.0)
                    cmd:set_sidemove(-math.sin(moveDir) * 450.0)
                end

                last_yaw = cur_yaw
            end
        end
    end

    was_on_ground = on_ground
end

-- =========================================================================
-- DESCARGA SEGURA
-- =========================================================================
function on_unload()
    client.set_extra_commands(0)
    just_jumped   = false
    was_on_ground = true
    client.print("[ByxV3] Descargado — Extra commands reseteados.")
end







