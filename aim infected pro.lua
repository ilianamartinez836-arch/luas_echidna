-- Aim Infected Pro (Rage Snap + Orbital Tracking) — Echidna (L4D2)
-- Manten MOUSE5 siendo Infectado para fijar supervivientes (incluso tras muros)
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_aiminfected_pro_instance = INSTANCE

pcall(ffi.cdef, [[ short GetAsyncKeyState(int vKey); ]])

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local VK_KEY_HOLD  = 0x06    -- Boton lateral MOUSE5 (XBUTTON2)
local MAX_DISTANCE = 8192.0  -- Rango maximo de fijacion

local function is_key_held()
    return bit.band(ffi.C.GetAsyncKeyState(VK_KEY_HOLD), 0x8000) ~= 0
end

local function normalize_yaw(y)
    while y > 180 do y = y - 360 end
    while y < -180 do y = y + 360 end
    return y
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function get_eye_pos(ent)
    if not ent then return nil end
    local eye = nil
    pcall(function() eye = ent:EyePosition() end)
    if eye and (eye.x or eye[1]) then return eye end
    local o = nil
    pcall(function() o = ent:get_origin() end)
    if o and (o.x or o[1]) then
        return { x = o.x or o[1], y = o.y or o[2], z = (o.z or o[3]) + 62.0 }
    end
    return nil
end

local function is_valid_target(p)
    if not p then return false end
    local alive = false
    pcall(function() alive = p:is_alive() end)
    if not alive then return false end

    -- Ignorar si esta muerto por salud
    local hp = 100
    pcall(function() hp = p:GetHealth() end)
    if hp and hp <= 0 then return false end

    -- Ignorar si esta incapacitado en el suelo
    local incap = false
    pcall(function() incap = p:is_incapacitated() end)
    if incap then return false end

    return true
end

-- =========================================================================
-- BUSQUEDA DEL MEJOR SUPERVIVIENTE (TEAM 2)
-- =========================================================================
local function get_best_survivor(my_pos)
    local best = nil
    local best_dist = MAX_DISTANCE
    local local_idx = EngineClient.GetLocalPlayer() or 0
    local max_ents = 32
    pcall(function() max_ents = EngineClient.GetMaxClients() or 32 end)

    for i = 1, max_ents do
        if i ~= local_idx then
            local ent = ClientEntityList.GetClientEntity(i)
            if ent and ent:is_valid() then
                local p = ent:as("CTerrorPlayer")
                -- Solo supervivientes (Team 2) vivos y de pie
                if p and p:get_team() == 2 and is_valid_target(p) then
                    local target_pos = get_eye_pos(p)
                    if target_pos then
                        local dx = target_pos.x - my_pos.x
                        local dy = target_pos.y - my_pos.y
                        local dz = target_pos.z - my_pos.z
                        local d = math.sqrt(dx * dx + dy * dy + dz * dz)

                        if d < best_dist then
                            best_dist = d
                            best = { ent = p, pos = target_pos }
                        end
                    end
                end
            end
        end
    end
    return best
end

-- =========================================================================
-- LOGICA EN CREATEMOVE (SNAP DIRECTO & ORBITAL LOCK)
-- =========================================================================
function on_create_move(cmd, lp)
    if _G.echidna_aiminfected_pro_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() or not lp or not lp:is_alive() then return end

    -- Solo cuando seamos Infectados (Team 3)
    local team = lp:get_team()
    if team ~= 3 then return end

    -- Solo mientras mantengamos presionado MOUSE5
    if not is_key_held() then return end

    local my_eye = get_eye_pos(lp)
    if not my_eye then return end

    local target = get_best_survivor(my_eye)
    if not target or not target.pos then return end

    -- Calculo matematico directo hacia el centro/cabeza del objetivo
    local dx = target.pos.x - my_eye.x
    local dy = target.pos.y - my_eye.y
    local dz = target.pos.z - my_eye.z
    local hyp = math.sqrt(dx * dx + dy * dy)
    if hyp < 0.001 then hyp = 0.001 end

    local pitch = math.deg(math.atan2(-dz, hyp))
    local yaw   = math.deg(math.atan2(dy, dx))

    -- Clamping y normalizacion de angulos para rotacion suave en 360 grados
    pitch = clamp(pitch, -89.0, 89.0)
    yaw   = normalize_yaw(yaw)

    local target_ang = { x = pitch, y = yaw, z = 0 }

    -- 1. Inyectar en el comando de movimiento
    cmd:set_viewangles(target_ang)

    -- 2. Snap en la camara del jugador (Rage directo)
    pcall(EngineClient.SetViewAngles, target_ang)
end

function on_unload()
    client.print("[AimInfected] Descargado.")
end

client.print("[AimInfected] Cargado — Manten MOUSE5 para fijar al superviviente mas cercano.")
