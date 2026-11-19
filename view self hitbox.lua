-- Desync Hitbox Visualizer (Ghost Hitbox 3D) — Echidna (L4D2)
-- Muestra la posicion real de tu Hitbox en el servidor mientras usas Choke
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_ghostbox_instance = INSTANCE

pcall(ffi.cdef, [[
    short GetAsyncKeyState(int vKey);
]])

-- =========================================================================
-- CONFIGURACION Y ESTETICA
-- =========================================================================
local CFG = {
    line_thick      = 1.5,
    min_desync_dist = 12.0, -- Distancia minima en unidades para empezar a dibujar
}

-- Colores: Blanco fantasma con toque celeste
local COLOR_BOX   = { 0.35, 0.85, 1.00, 0.85 } -- Caja 3D (Cyan / Fantasma)
local COLOR_LINE  = { 1.00, 1.00, 1.00, 0.60 } -- Linea conectora (Blanco suave)
local COLOR_TEXT  = { 1.00, 1.00, 1.00, 1.00 } -- Texto

-- =========================================================================
-- RASTREO DE COORDENADAS
-- =========================================================================
local last_sent_origin = nil
local last_sent_duck   = false
local is_choking_now   = false

local function w2s(x, y, z)
    local p = visual.world_to_screen(x, y, z)
    if p and (p.x or p[1]) then
        return { x = p.x or p[1], y = p.y or p[2] }
    end
    return nil
end

-- Deteccion de choke y captura de posicion en CreateMove
function on_create_move(cmd, lp)
    if not lp or not lp:is_alive() or not EngineClient.IsInGame() then
        last_sent_origin = nil
        return
    end

    local cur_origin = lp:get_origin()
    if not cur_origin then return end

    -- Detectar si hay choke activo (verificando si la tecla C esta apretada o si hay choke de red)
    local nc = EngineClient.GetNetChannelInfo()
    local is_choked = false

    if nc and not nc:IsNull() then
        local chk = nc:m_nChokedPackets() or 0
        if chk > 1 then is_choked = true end
    end

    -- Tecla C (Hold del Master Choke)
    local key_c = bit.band(ffi.C.GetAsyncKeyState(0x43), 0x8000) ~= 0
    if key_c then is_choked = true end

    -- Si no estamos chokeando, actualizamos la posicion del servidor
    if not is_choked then
        last_sent_origin = { x = cur_origin.x, y = cur_origin.y, z = cur_origin.z }
        local p = lp:as("CTerrorPlayer")
        last_sent_duck = p and (p:is_ducked() or p:is_ducking()) or false
    end

    is_choking_now = is_choked
end

-- =========================================================================
-- DIBUJO DE LA HITBOX FANTASMA 3D (END SCENE)
-- =========================================================================
function on_end_scene()
    if _G.echidna_ghostbox_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() or not last_sent_origin then return end

    local lp = EntityCache.GetLocal()
    if not lp or not lp:is_alive() then return end

    local cur_origin = lp:get_origin()
    if not cur_origin then return end

    -- Calcular distancia del Desync
    local dx = cur_origin.x - last_sent_origin.x
    local dy = cur_origin.y - last_sent_origin.y
    local dz = cur_origin.z - last_sent_origin.z
    local dist_units = math.sqrt(dx * dx + dy * dy + dz * dz)

    -- Solo dibujar si la hitbox real se separo de nuestro cuerpo
    if dist_units < CFG.min_desync_dist then return end

    local dl = imgui.get_foreground_draw_list()

    -- Dimensiones de la caja de un superviviente/jugador en Source
    local height = last_sent_duck and 54.0 or 72.0
    local hw = 16.0 -- Ancho medio (radio 16x16)

    local ox = last_sent_origin.x
    local oy = last_sent_origin.y
    local oz = last_sent_origin.z

    -- Los 8 vertices de la caja 3D en el mundo
    local v = {
        w2s(ox - hw, oy - hw, oz),          -- 1: Abajo Izquierda Atras
        w2s(ox + hw, oy - hw, oz),          -- 2: Abajo Derecha Atras
        w2s(ox + hw, oy + hw, oz),          -- 3: Abajo Derecha Frente
        w2s(ox - hw, oy + hw, oz),          -- 4: Abajo Izquierda Frente
        w2s(ox - hw, oy - hw, oz + height), -- 5: Arriba Izquierda Atras
        w2s(ox + hw, oy - hw, oz + height), -- 6: Arriba Derecha Atras
        w2s(ox + hw, oy + hw, oz + height), -- 7: Arriba Derecha Frente
        w2s(ox - hw, oy + hw, oz + height), -- 8: Arriba Izquierda Frente
    }

    local r, g, b, a = COLOR_BOX[1], COLOR_BOX[2], COLOR_BOX[3], COLOR_BOX[4]
    local th = CFG.line_thick

    local function draw_edge(i1, i2)
        if v[i1] and v[i2] then
            dl:add_line(v[i1].x, v[i1].y, v[i2].x, v[i2].y, r, g, b, a, th)
        end
    end

    -- 1. Base cuadrada inferior
    draw_edge(1, 2)
    draw_edge(2, 3)
    draw_edge(3, 4)
    draw_edge(4, 1)

    -- 2. Techo cuadrado superior
    draw_edge(5, 6)
    draw_edge(6, 7)
    draw_edge(7, 8)
    draw_edge(8, 5)

    -- 3. Pilares verticales conectores
    draw_edge(1, 5)
    draw_edge(2, 6)
    draw_edge(3, 7)
    draw_edge(4, 8)

    -- 4. Linea conectora (Tracer) desde tu cuerpo actual hasta el centro de la hitbox fantasma
    local s_cur = w2s(cur_origin.x, cur_origin.y, cur_origin.z + 36.0)
    local s_ghost = w2s(ox, oy, oz + (height * 0.5))

    if s_cur and s_ghost then
        dl:add_line(s_cur.x, s_cur.y, s_ghost.x, s_ghost.y,
            COLOR_LINE[1], COLOR_LINE[2], COLOR_LINE[3], COLOR_LINE[4], 1.2)
    end

    -- 5. Etiqueta flotante encima de la hitbox fantasma
    local s_top = w2s(ox, oy, oz + height + 6.0)
    if s_top then
        local dist_meters = dist_units / 52.5 -- Conversion de unidades Source a metros
        local text = string.format("[GHOST HITBOX] %.1fm (%d u)", dist_meters, math.floor(dist_units))
        local tw = imgui.CalcTextSize(text)
        
        -- Fondo negro para el texto
        dl:add_rect_filled(s_top.x - tw * 0.5 - 4, s_top.y - 14, s_top.x + tw * 0.5 + 4, s_top.y + 2, 0.05, 0.05, 0.08, 0.85, 3)
        dl:add_text(s_top.x - tw * 0.5, s_top.y - 13, COLOR_TEXT[1], COLOR_TEXT[2], COLOR_TEXT[3], 1.0, text)
    end
end

function on_unload()
    last_sent_origin = nil
    client.print("[GhostHitbox] Descargado.")
end

client.print("[GhostHitbox] Cargado — Dibuja tu hitbox real del servidor al hacer Desync.")
