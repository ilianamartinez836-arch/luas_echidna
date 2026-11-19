-- Tank Frustration Widget (Esquina Derecha Abajo) — Echidna (L4D2)
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_tankfrust_instance = INSTANCE

local function rgba(r, g, b, a)
    return { r/255, g/255, b/255, (a or 255)/255 }
end

local function c(t, ...)
    return t[1], t[2], t[3], t[4], ...
end

-- =========================================================================
-- CONFIGURACION Y ESTETICA BLACK & WHITE
-- =========================================================================
local CFG = {
    w        = 210,    -- Ancho del panel
    h        = 56,     -- Altura del panel
    offset_x = 20,     -- Margen desde el borde derecho
    offset_y = 120,    -- Margen desde el borde inferior (un poco mas arriba del HUD)
    rounding = 8,
}

local C = {
    bg      = rgba(12, 12, 12, 185),     -- Fondo negro ahumado
    hdr     = rgba(20, 20, 20, 235),     -- Encabezado oscuro
    border  = rgba(255, 255, 255, 40),  -- Borde blanco suave
    title   = rgba(255, 255, 255, 255), -- Titulo blanco
    label   = rgba(170, 170, 170, 255), -- Nombre del Tank
    bar_bg  = rgba(30, 30, 30, 220),    -- Fondo de la barra
    bar_fill= rgba(255, 255, 255, 240), -- Relleno de la barra blanco
    bar_crit= rgba(255, 70,  70,  255), -- Rojo si esta a punto de perder el control (< 20%)
}

local frust_smooth = 100.0

-- =========================================================================
-- BUSCAR AL TANK ACTIVO
-- =========================================================================
local function get_active_tank()
    local max_ents = 32
    pcall(function()
        local m = EngineClient.GetMaxClients()
        if type(m) == "number" and m > 0 then max_ents = m end
    end)

    for i = 1, max_ents do
        local ent = ClientEntityList.GetClientEntity(i)
        if ent and ent:is_valid() then
            local p = ent:as("CTerrorPlayer")
            if p and p:is_alive() and p:get_team() == 3 and p:get_zombie_class() == 8 then
                local frust = 0
                pcall(function()
                    frust = p:get_prop_int("CTerrorPlayer", "m_frustration") or 0
                end)
                
                local name = nil
                local info = EngineClient.GetPlayerInfo(i)
                if info and info:name() ~= "" then name = info:name() end
                name = (name and name ~= "") and name or ("Tank#" .. i)

                return {
                    name = name,
                    frustration = frust
                }
            end
        end
    end
    return nil
end

-- =========================================================================
-- RENDER (IMGUI DRAWLIST)
-- =========================================================================
function on_end_scene()
    if _G.echidna_tankfrust_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    local tank = get_active_tank()
    if not tank then
        frust_smooth = 100.0
        return
    end

    -- Suavizado matematico del porcentaje
    frust_smooth = frust_smooth + (tank.frustration - frust_smooth) * 0.1
    local val = math.max(0, math.min(100, frust_smooth))

    -- Obtener dimensiones de pantalla para colocar en la esquina inferior derecha
    local sw, sh = 1920, 1080
    local ok_scr, w_s, h_s = pcall(EngineClient.GetScreenSize)
    if ok_scr and type(w_s) == "number" and w_s > 0 then
        sw, sh = w_s, h_s
    end

    local px = sw - CFG.w - CFG.offset_x
    local py = sh - CFG.h - CFG.offset_y

    local dl = imgui.get_foreground_draw_list()

    -- 1. Fondo principal
    dl:add_rect_filled(px, py, px + CFG.w, py + CFG.h, c(C.bg, CFG.rounding))

    -- 2. Titulo y Nombre del Tank
    local title_str = "Tank Frustration"
    dl:add_text(px + 10, py + 7, c(C.title, title_str))

    local name_str = tank.name
    local nw = imgui.CalcTextSize(name_str)
    -- Si el nombre es muy largo lo acorta
    dl:add_text(px + CFG.w - 10 - nw, py + 7, c(C.label, name_str))

    -- 3. Barra de Progreso
    local bar_x = px + 10
    local bar_y = py + 28
    local bar_w = CFG.w - 20
    local bar_h = 10

    -- Fondo de la barra
    dl:add_rect_filled(bar_x, bar_y, bar_x + bar_w, bar_y + bar_h, c(C.bar_bg, 3))

    -- Relleno de la barra (Rojo si le queda poca frustracion, blanco normal)
    local fill_w = bar_w * (val / 100.0)
    local fill_col = (val <= 25) and C.bar_crit or C.bar_fill
    if fill_w > 0 then
        dl:add_rect_filled(bar_x, bar_y, bar_x + fill_w, bar_y + bar_h, c(fill_col, 3))
    end

    -- 4. Texto del Porcentaje numerico
    local pct_str = string.format("%d%%", math.floor(val + 0.5))
    local pw = imgui.CalcTextSize(pct_str)
    dl:add_text(px + (CFG.w - pw) * 0.5, py + 41, c(C.title, pct_str))

    -- 5. Borde exterior elegante
    dl:add_rect(px, py, px + CFG.w, py + CFG.h, c(C.border, 1.0, CFG.rounding))
end

function on_unload()
    client.print("[TankFrust] Descargado.")
end

client.print("[TankFrust] Cargado — Barra activa en esquina inferior derecha.")
