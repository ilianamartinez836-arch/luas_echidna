-- Speedbunny (Bhop + Ground Extra-Cmds Boost + Auto-Strafe) — Echidna (L4D2)
-- Manten ESPACIO para acelerar en cada salto

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local EXTRA_CMDS_AMOUNT = 3     -- Comandos extra inyectados al tocar el suelo (Recomendado: 3 a 10)
local ENABLE_STRAFER    = true  -- Activar Auto-Strafer en el aire (true / false)
local STRAFE_SPEED      = 450   -- Fuerza de strafe lateral (max 450)

-- =========================================================================
-- ESTADO INTERNO
-- =========================================================================
local IN_JUMP       = 1 * 2     -- Bit 2 (IN_JUMP)
local is_space_held = false
local just_landed   = false
local was_on_ground = false
local last_yaw      = 0

local function has_bit(val, bitmask)
    return math.floor(val / bitmask) % 2 == 1
end

-- =========================================================================
-- INYECCION DE EXTRA COMMANDS (CL_MOVE PRE)
-- =========================================================================
function on_cl_move_pre()
    if not EngineClient.IsInGame() then
        client.set_extra_commands(0)
        return
    end

    -- Si estamos manteniendo espacio y acabamos de tocar suelo para saltar -> BOOST!
    if is_space_held and just_landed then
        client.set_extra_commands(EXTRA_CMDS_AMOUNT)
        just_landed = false
    else
        client.set_extra_commands(0)
    end
end

-- =========================================================================
-- LOGICA DE BHOP Y AUTO-STRAFE EN CREATEMOVE
-- =========================================================================
function on_create_move(cmd, lp)
    if not cmd or not lp or not lp:is_alive() then
        is_space_held = false
        just_landed   = false
        was_on_ground = false
        return
    end

    local buttons = cmd:get_buttons() or 0
    is_space_held = has_bit(buttons, IN_JUMP)

    if not is_space_held then
        was_on_ground = lp:is_on_ground()
        just_landed   = false
        return
    end

    local on_ground = lp:is_on_ground()

    -- 1. Deteccion de contacto con el suelo para disparar el boost
    if on_ground and not was_on_ground then
        just_landed = true
    end

    -- 2. Bunnyhop: forzar salto en el suelo, soltar en el aire
    if on_ground then
        cmd:add_button(IN_JUMP)
    else
        cmd:remove_button(IN_JUMP)

        -- 3. Auto-Strafer en el aire
        if ENABLE_STRAFER then
            local ang = cmd:get_viewangles()
            local cur_yaw = ang and (ang.y or ang[2] or 0) or 0
            local yaw_delta = cur_yaw - last_yaw

            -- Normalizar delta de yaw (-180 a 180)
            while yaw_delta > 180 do yaw_delta = yaw_delta - 360 end
            while yaw_delta < -180 do yaw_delta = yaw_delta + 360 end

            local mouse_dx = cmd:get_mousedx() or 0

            -- Strafe segun giro de raton o delta de vista
            if mouse_dx < 0 or yaw_delta > 0 then
                cmd:set_sidemove(-STRAFE_SPEED)
            elseif mouse_dx > 0 or yaw_delta < 0 then
                cmd:set_sidemove(STRAFE_SPEED)
            end
        end
    end

    local current_ang = cmd:get_viewangles()
    last_yaw = current_ang and (current_ang.y or current_ang[2] or 0) or 0
    was_on_ground = on_ground
end

-- =========================================================================
-- DESCARGA
-- =========================================================================
function on_unload()
    client.set_extra_commands(0)
    client.print("[Speedbunny] Descargado — Extra commands reseteados.")
end

client.print("[Speedbunny] Cargado — ExtraCmds: " .. tostring(EXTRA_CMDS_AMOUNT) .. " | Strafer: " .. tostring(ENABLE_STRAFER))






