-- Tank Lottery Widget (Esquina Izquierda Abajo) — Echidna (L4D2)
-- Misma altura que Tank Frustration, alineado a la izquierda
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_tanklottery_instance = INSTANCE

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
    w        = 220,    -- Mismo ancho que Tank Frustration
    offset_x = 20,     -- Margen desde el borde izquierdo (20px)
    offset_y = 120,    -- Misma altura que Tank Frustration (120px desde abajo)
    row_h    = 18,
    gap      = 3,
    pad_x    = 10,
    pad_y    = 8,
    hdr_h    = 24,
    rounding = 8,
}

local C = {
    bg      = rgba(12, 12, 12, 185),     -- Fondo negro ahumado
    hdr     = rgba(20, 20, 20, 235),     -- Encabezado oscuro
    border  = rgba(255, 255, 255, 40),  -- Borde blanco suave
    title   = rgba(255, 255, 255, 255), -- Titulo blanco
    label   = rgba(175, 175, 175, 255), -- Nombre del jugador
    pct     = rgba(255, 255, 255, 255), -- Porcentaje blanco
    next    = rgba(255, 215, 80,  255), -- [NEXT] en amarillo suave destacado
    dot     = rgba(255, 255, 255, 220), -- Punto blanco indicador
    sep     = rgba(255, 255, 255, 25),
}

-- =========================================================================
-- BUSCAR RECURSOS DE JUGADOR (CTerrorPlayerResource)
-- =========================================================================
local function get_player_resource()
    local max_ents = 64
    pcall(function() max_ents = ClientEntityList.GetHighestEntityIndex() or 64 end)

    for i = 1, max_ents do
        local ent = ClientEntityList.GetClientEntity(i)
        if ent and ent:is_valid() then
            local cls = ent:get_class_name()
            if cls == "CTerrorPlayerResource" then
                return ent
            end
        end
    end
    return nil
end

local function get_lottery_ratio(pr, idx)
    if not pr then return 0 end
    local ratio = 0

    -- Probar multiples formatos de array de red de Source Engine
    pcall(function()
        ratio = pr:get_prop_float("CTerrorPlayerResource", "m_tankLotterySelectionRatio", idx)
    end)
    if not ratio or ratio <= 0 then
        pcall(function()
            ratio = pr:get_prop_float("CTerrorPlayerResource", string.format("m_tankLotterySelectionRatio.%03d", idx - 1))
        end)
    end
    if not ratio or ratio <= 0 then
        pcall(function()
            ratio = pr:get_prop_float("CTerrorPlayerResource", string.format("m_tankLotterySelectionRatio.%03d", idx))
        end)
    end

    return ratio or 0
end

-- =========================================================================
-- RECOLECTAR Y ORDENAR DATOS DE LOTERIA
-- =========================================================================
local function get_lottery_data()
    local out = {}
    if not EngineClient.IsInGame() then return out end

    local pr = get_player_resource()
    if not pr then return out end

    local max_clients = 32
    pcall(function()
        local m = EngineClient.GetMaxClients()
        if type(m) == "number" and m > 0 then max_clients = m end
    end)

    local highest = -1

    for i = 1, max_clients do
        local ent = ClientEntityList.GetClientEntity(i)
        if ent and ent:is_valid() then
            local p = ent:as("CTerrorPlayer")
            -- Infectados (Team 3)
            if p and p:get_team() == 3 then
                local ratio = get_lottery_ratio(pr, i)

                if ratio and ratio > 0 then
                    if ratio > highest then highest = ratio end

                    local name = nil
                    local info = EngineClient.GetPlayerInfo(i)
                    if info and info:name() ~= "" then name = info:name() end
                    name = (name and name ~= "") and name or ("Player#" .. i)

                    out[#out + 1] = {
                        name  = name,
                        ratio = ratio,
                        idx   = i
                    }
                end
            end
        end
    end

    if #out == 0 then return out end

    -- Ordenar de mayor a menor porcentaje
    table.sort(out, function(a, b) return a.ratio > b.ratio end)

    -- Marcar al que tiene el porcentaje mas alto como [NEXT]
    for _, d in ipairs(out) do
        d.is_next = (highest > 0 and math.abs(d.ratio - highest) < 0.001)
    end

    return out
end

-- =========================================================================
-- RENDER (IMGUI DRAWLIST)
-- =========================================================================
function on_end_scene()
    if _G.echidna_tanklottery_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    local lottery = get_lottery_data()
    if #lottery == 0 then return end

    -- Dimensiones de pantalla
    local sw, sh = 1920, 1080
    local ok_scr, w_s, h_s = pcall(EngineClient.GetScreenSize)
    if ok_scr and type(w_s) == "number" and w_s > 0 then
        sw, sh = w_s, h_s
    end

    -- Calcular altura segun cantidad de jugadores en la loteria
    local total_rows_h = #lottery * CFG.row_h + (#lottery - 1) * CFG.gap
    local panel_h = CFG.hdr_h + CFG.pad_y * 2 + total_rows_h

    -- Posicionar en la izquierda a la misma altura que Tank Frustration
    local px = CFG.offset_x
    local py = sh - panel_h - CFG.offset_y

    local dl = imgui.get_foreground_draw_list()

    -- 1. Fondo principal
    dl:add_rect_filled(px, py, px + CFG.w, py + panel_h, c(C.bg, CFG.rounding))

    -- 2. Encabezado oscuro con esquinas redondeadas
    dl:add_rect_filled(px, py, px + CFG.w, py + CFG.hdr_h, c(C.hdr, CFG.rounding))
    local half = math.ceil(CFG.rounding)
    dl:add_rect_filled(px, py + CFG.hdr_h - half, px + CFG.w, py + CFG.hdr_h, c(C.hdr, 0))
    dl:add_line(px + 6, py + CFG.hdr_h, px + CFG.w - 6, py + CFG.hdr_h, c(C.sep, 1.0))

    -- 3. Titulo centrado
    local title = string.format("Tank Lottery (%d)", #lottery)
    local tw = imgui.CalcTextSize(title)
    dl:add_text(px + (CFG.w - tw) * 0.5, py + (CFG.hdr_h - 13) * 0.5, c(C.title, title))

    -- 4. Filas de jugadores con sus porcentajes
    local cy = py + CFG.hdr_h + CFG.pad_y
    for _, d in ipairs(lottery) do
        local dot_x = px + CFG.pad_x + 4
        local dot_y = cy + CFG.row_h * 0.5
        local ty    = cy + (CFG.row_h - 13) * 0.5

        -- Punto indicador blanco
        dl:add_circle_filled(dot_x, dot_y, 2.5, c(C.dot))

        -- Nombre del jugador
        local name_txt = d.name
        if #name_txt > 12 then name_txt = name_txt:sub(1, 11) .. "…" end
        dl:add_text(dot_x + 8, ty, c(C.label, name_txt))

        -- Porcentaje y badge [NEXT]
        local pct_txt = string.format("%.1f%%", d.ratio * 100)
        local right_txt = d.is_next and (pct_txt .. "  NEXT") or pct_txt
        local rw = imgui.CalcTextSize(right_txt)
        local rx = px + CFG.w - CFG.pad_x - rw

        if d.is_next then
            local pw = imgui.CalcTextSize(pct_txt)
            dl:add_text(rx, ty, c(C.pct, pct_txt))
            dl:add_text(rx + pw + 8, ty, c(C.next, "NEXT"))
        else
            dl:add_text(rx, ty, c(C.pct, pct_txt))
        end

        cy = cy + CFG.row_h + CFG.gap
    end

    -- 5. Borde exterior
    dl:add_rect(px, py, px + CFG.w, py + panel_h, c(C.border, 1.0, CFG.rounding))
end

function on_unload()
    client.print("[TankLottery] Descargado.")
end

client.print("[TankLottery] Cargado — Ubicado a la izquierda a la altura de Frustration.")
