-- Tank Rock Aimbot (Rage Mode - Direct Snap al Centro) — Echidna (L4D2)
local ffi = require("ffi")

pcall(ffi.cdef, [[ short GetAsyncKeyState(int vKey); ]])

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local VK_MOUSE5 = 0x06 -- Mouse 5
local FOV_MAX   = 90.0 -- Subido un poco para que atrape la roca mas rapido

local function is_key_held()
    return bit.band(ffi.C.GetAsyncKeyState(VK_MOUSE5), 0x8000) ~= 0
end

local function normalize_yaw(y)
    while y > 180 do y = y - 360 end
    while y < -180 do y = y + 360 end
    return y
end

local function get_entity_pos(ent)
    if not ent then return nil end
    local pos = nil
    pcall(function()
        if ent.get_render_origin then pos = ent:get_render_origin() end
        if not pos and ent.get_origin then pos = ent:get_origin() end
        if not pos and ent.GetRenderOrigin then pos = ent:GetRenderOrigin() end
    end)
    return pos
end

local function get_rock()
    local tank = nil
    local max_ents = 32
    pcall(function() max_ents = ClientEntityList.GetHighestEntityIndex() or 32 end)

    -- 1. Buscar al Tank
    for i = 1, max_ents do
        local ent = ClientEntityList.GetClientEntity(i)
        if ent and ent:is_valid() then
            local p = ent:as("CTerrorPlayer")
            if p and p.get_zombie_class and p:get_zombie_class() == 8 and p:is_alive() then
                tank = p
                break
            end
        end
    end
    if not tank then return nil end

    local tankPos = get_entity_pos(tank)
    if not tankPos then return nil end

    local best = nil
    local bestDist = 99999

    -- 2. Buscar la roca mas cercana al Tank
    for i = 33, max_ents do
        local ent = ClientEntityList.GetClientEntity(i)
        if ent and ent:is_valid() and ent:get_class_name() == "CBaseCSGrenadeProjectile" then
            local pos = get_entity_pos(ent)
            if pos then
                local dist = math.sqrt((pos.x - tankPos.x)^2 + (pos.y - tankPos.y)^2 + (pos.z - tankPos.z)^2)
                if dist < bestDist then
                    bestDist = dist
                    best = ent
                end
            end
        end
    end
    return best
end

function on_create_move(cmd, lp)
    if not lp or not lp:is_alive() or not is_key_held() then return end
    
    local rock = get_rock()
    if not rock then return end

    local myPos = lp:EyePosition()
    local rockPos = get_entity_pos(rock)
    if not myPos or not rockPos then return end

    -- APUNTAR DIRECTO AL CENTRO DE LA ROCA (SIN OFFSETS NI PREDICCION FALSA)
    local delta = { 
        x = rockPos.x - myPos.x, 
        y = rockPos.y - myPos.y, 
        z = rockPos.z - myPos.z 
    }
    
    local hyp = math.sqrt(delta.x * delta.x + delta.y * delta.y)
    local pitch = math.deg(math.atan2(-delta.z, hyp))
    local yaw   = math.deg(math.atan2(delta.y, delta.x))

    local view = cmd:get_viewangles()
    if not view then return end

    local cur_pitch = view.x or view[1] or 0
    local cur_yaw   = view.y or view[2] or 0

    local dy = normalize_yaw(yaw - cur_yaw)
    local dx = pitch - cur_pitch
    local fov = math.sqrt(dx * dx + dy * dy)
    
    if fov <= FOV_MAX then
        local new_ang = { x = pitch, y = yaw, z = 0 }
        
        -- Snap directo en el comando y en la camara
        cmd:set_viewangles(new_ang)
        pcall(EngineClient.SetViewAngles, new_ang)
    end
end

function on_unload()
    client.print("[TankRock] Descargado.")
end

client.print("[TankRock] Cargado — Modo Rage directo al centro de la roca.")
