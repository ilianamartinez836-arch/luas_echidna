-- Simple Player Name ESP (Con detector de BOT) — Echidna (L4D2)
local INSTANCE = {}
_G.echidna_playernames_instance = INSTANCE

local function w2s(x, y, z)
    local p = visual.world_to_screen(x, y, z)
    if p and (p.x or p[1]) then
        return { x = p.x or p[1], y = p.y or p[2] }
    end
    return nil
end

function on_end_scene()
    if _G.echidna_playernames_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    local local_idx = EngineClient.GetLocalPlayer()
    local max_clients = 32
    pcall(function() max_clients = EngineClient.GetMaxClients() or 32 end)

    local dl = imgui.get_foreground_draw_list()

    for i = 1, max_clients do
        if i ~= local_idx then
            local ent = ClientEntityList.GetClientEntity(i)
            if ent and ent:is_valid() and not ent:is_dormant() then
                local p = ent:as("CTerrorPlayer")
                if p and p:is_alive() then
                    -- 1. Obtener posicion de la cabeza / ojos
                    local eye_pos = p:EyePosition()
                    local origin = p:get_origin()

                    local top_z = eye_pos and (eye_pos.z + 14.0) or (origin and (origin.z + 76.0))

                    if origin and top_z then
                        local screen_pos = w2s(origin.x, origin.y, top_z)

                        if screen_pos then
                            -- 2. Obtener Nombre del jugador
                            local name = nil
                            local is_bot = false

                            local p_info = EngineClient.GetPlayerInfo(i)
                            if p_info then
                                name = p_info:name()
                                -- En Source Engine, los bots de L4D2 tienen amigosid en 0 o guid específico
                                if p_info:friendsid() == 0 or p_info:guid() == "BOT" or p_info:guid() == "STEAM_ID_LAN" then
                                    is_bot = true
                                end
                            end

                            -- Comprobar si la entidad es bot nativo
                            if p.IsBot and p:IsBot() then
                                is_bot = true
                            end

                            local class_name = ent:get_class_name() or ""
                            if class_name == "SurvivorBot" then
                                is_bot = true
                            end

                            name = (name and name ~= "" and name ~= "unconnected") and name or ("Player#" .. i)

                            if is_bot then
                                name = name .. " [BOT]"
                            end

                            -- 3. Color segun equipo
                            local team = p:get_team()
                            local r, g, b = 1.0, 1.0, 1.0
                            if team == 2 then
                                r, g, b = 0.4, 0.8, 1.0 -- Supervivientes (Celeste)
                            elseif team == 3 then
                                r, g, b = 1.0, 0.35, 0.35 -- Infectados (Rojo suave)
                            end

                            -- 4. Dibujar fondo negro sutil y texto centrado
                            local tw = imgui.CalcTextSize(name)
                            local tx = screen_pos.x - tw * 0.5
                            local ty = screen_pos.y - 12

                            dl:add_rect_filled(tx - 3, ty - 1, tx + tw + 3, ty + 13, 0.05, 0.05, 0.08, 0.75, 3)
                            dl:add_text(tx, ty, r, g, b, 1.0, name)
                        end
                    end
                end
            end
        end
    end
end

function on_unload()
    client.print("[PlayerNames] Descargado.")
end

client.print("[PlayerNames] Cargado — Mostrando nombres arriba de la cabeza.")
