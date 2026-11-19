-- Spectator List — Black & White Floating Panel (Echidna L4D2)
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_speclist_instance = INSTANCE

local function rgba(r, g, b, a)
    return { r/255, g/255, b/255, (a or 255)/255 }
end

local function ca(col, scale)
    return col[1], col[2], col[3], col[4] * (scale or 1)
end

local function c(t, ...)
    return t[1], t[2], t[3], t[4], ...
end

-- =========================================================================
-- CONFIGURACION Y TEMA BLACK & WHITE (IDÉNTICO A KEYBINDLIST)
-- =========================================================================
local CFG = {
    x        = 300,      -- Posición X inicial
    y        = 14,     -- Posición Y inicial (debajo del keybind list)
    w        = 195,     -- Mismo ancho que keybind list
    pad_x    = 10,
    pad_y    = 7,
    row_h    = 17,
    gap      = 3,
    rounding = 8,
    hdr_h    = 24,
    spd      = 14,      -- Velocidad de animación
}

local C = {
    bg       = rgba(12, 12, 12, 180),     -- Fondo negro ahumado semi-transparente
    hdr      = rgba(20, 20, 20, 230),     -- Encabezado oscuro
    hdr_txt  = rgba(255, 255, 255, 255), -- Titulo "Spectators" blanco puro
    sep      = rgba(255, 255, 255, 25),  -- Separador blanco sutil
    border   = rgba(255, 255, 255, 40),  -- Borde blanco suave
    text     = rgba(255, 255, 255, 255), -- Nombre del espectador en blanco
    dot      = rgba(255, 255, 255, 230), -- Punto indicador blanco
    mode     = rgba(160, 160, 160, 255), -- Modo [1ST] / [3RD] en gris plateado
}

local OBS_MODES = {
    [4] = "[1ST]",  -- In-Eye (Primera persona)
    [5] = "[3RD]",  -- Chase (Tercera persona)
}

-- =========================================================================
-- ESTADO Y ANIMACIONES
-- =========================================================================
local drag       = { on = false, ox = 0, oy = 0, sx = 0, sy = 0, moved = false }
local mb_prev    = false
local last_t     = os.clock()
local anim_h     = 0.0
local spectators = {}
local last_scan  = 0

-- Escaneo de espectadores que te están observando
local function scan_spectators()
    local now = os.clock()
    if now - last_scan < 0.15 then return spectators end
    last_scan = now

    local out = {}
    if not EngineClient.IsInGame() then return out end

    local local_idx = EngineClient.GetLocalPlayer()
    if not local_idx or local_idx <= 0 then return out end

    local max_clients = 32
    pcall(function()
        local m = EngineClient.GetMaxClients()
        if type(m) == "number" and m > 0 then max_clients = m end
    end)

    for i = 1, max_clients do
        if i ~= local_idx then
            local ent = ClientEntityList.GetClientEntity(i)
            if ent and ent:is_valid() then
                local p = ent:as("CTerrorPlayer")
                if p then
                    local mode = 0
                    local target = -1

                    pcall(function()
                        mode   = p:get_prop_int("CBasePlayer", "m_iObserverMode")
                        target = p:get_prop_int("CBasePlayer", "m_hObserverTarget")
                    end)

                    -- Si está en modo espectador y su objetivo somos nosotros
                    if mode and mode > 0 and target and target > 0 then
                        local target_idx = target % 2048
                        if target_idx == local_idx then
                            local name = nil
                            local p_info = EngineClient.GetPlayerInfo(i)
                            if p_info then name = p_info:name() end
                            name = (name and name ~= "") and name or ("Player#" .. i)

                            out[#out + 1] = {
                                name = name,
                                mode = OBS_MODES[mode] or "[SPEC]"
                            }
                        end
                    end
                end
            end
        end
    end

    spectators = out
    return spectators
end

-- =========================================================================
-- RENDER Y DIBUJO (IMGUI)
-- =========================================================================
local function draw()

    local now = os.clock()
    local dt  = math.min(now - last_t, 0.05)
    last_t    = now

    local k   = 1.0 - math.exp(-CFG.spd * dt)
    local dl  = imgui.get_foreground_draw_list()
    local mx, my = imgui.GetMousePos()
    local mb  = imgui.IsMouseDown(0)

    local just_dn = mb and not mb_prev
    local just_up = not mb and mb_prev
    mb_prev = mb

    local px, py = CFG.x, CFG.y

    -- Arrastre con el ratón
    if just_dn then
        if mx >= px and mx <= px + CFG.w and my >= py and my <= py + CFG.hdr_h then
            drag.on    = true
            drag.ox    = mx - CFG.x
            drag.oy    = my - CFG.y
            drag.sx    = mx
            drag.sy    = my
            drag.moved = false
        end
    end

    if drag.on and mb then
        if math.abs(mx - drag.sx) + math.abs(my - drag.sy) > 4 then drag.moved = true end
        if drag.moved then
            CFG.x = mx - drag.ox
            CFG.y = my - drag.oy
            px, py = CFG.x, CFG.y
        end
    end

    if just_up then drag.on = false end

    -- Escaneo de espectadores
    local specs = scan_spectators()

    -- Altura animada según cantidad de espectadores
    local target_h = 0
    if #specs > 0 then
        target_h = #specs * (CFG.row_h + CFG.gap) - CFG.gap
    end

    anim_h = anim_h + (target_h - anim_h) * k
    local has_content = anim_h > 1.0

    local panel_h = CFG.hdr_h + (has_content and (CFG.pad_y * 2 + anim_h) or 0)

    -- Fondo general
    dl:add_rect_filled(px, py, px + CFG.w, py + panel_h, c(C.bg, CFG.rounding))

    -- Encabezado oscuro
    dl:add_rect_filled(px, py, px + CFG.w, py + CFG.hdr_h, c(C.hdr, CFG.rounding))
    if has_content then
        local half = math.ceil(CFG.rounding)
        dl:add_rect_filled(px, py + CFG.hdr_h - half, px + CFG.w, py + CFG.hdr_h, c(C.hdr, 0))
        dl:add_line(px + 6, py + CFG.hdr_h, px + CFG.w - 6, py + CFG.hdr_h, c(C.sep, 1.0))
    end

    -- Título centrado "Spectators"
    local title = string.format("Spectators (%d)", #specs)
    local tw    = imgui.CalcTextSize(title)
    dl:add_text(px + (CFG.w - tw) * 0.5, py + (CFG.hdr_h - 13) * 0.5, c(C.hdr_txt, title))

    -- Filas de espectadores
    if has_content then
        local cy = py + CFG.hdr_h + CFG.pad_y
        for i, s in ipairs(specs) do
            local dot_x = px + CFG.pad_x + 4
            local dot_y = cy + CFG.row_h * 0.5
            local ty    = cy + (CFG.row_h - 13) * 0.5

            -- Punto indicador
            dl:add_circle_filled(dot_x, dot_y, 3.0, c(C.dot))

            -- Nombre del espectador
            dl:add_text(dot_x + 9, ty, c(C.text, s.name))

            -- Modo [1ST] / [3RD] a la derecha
            local mw = imgui.CalcTextSize(s.mode)
            local bx = px + CFG.w - CFG.pad_x - mw
            dl:add_text(bx, ty, c(C.mode, s.mode))

            cy = cy + CFG.row_h + CFG.gap
        end
    end

    -- Borde exterior
    dl:add_rect(px, py, px + CFG.w, py + panel_h, c(C.border, 1.0, CFG.rounding))
end

function on_end_scene()
    if _G.echidna_speclist_instance ~= INSTANCE then return end
    pcall(draw)
end

function on_unload()
    drag.on = false
    mb_prev = false
    spectators = {}
    client.print("[SpectatorList] Descargado.")
end

client.print("[SpectatorList] Cargado — Mismo diseño Black & White.")




