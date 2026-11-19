-- Network & Session Stats Overlay — Black & White (Echidna L4D2)
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_netoverlay_instance = INSTANCE

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
    x        = 1020,      -- Posicion inicial X
    y        = 14,      -- Posicion inicial Y
    w        = 245,     -- Ancho del panel
    pad_x    = 10,
    pad_y    = 8,
    row_h    = 18,
    gap      = 3,
    rounding = 8,
    hdr_h    = 24,
}

local C = {
    bg       = rgba(12, 12, 12, 185),     -- Fondo negro ahumado
    hdr      = rgba(20, 20, 20, 235),     -- Encabezado oscuro
    hdr_txt  = rgba(255, 255, 255, 255), -- Titulo blanco puro
    sep      = rgba(255, 255, 255, 25),  -- Separador blanco sutil
    border   = rgba(255, 255, 255, 40),  -- Borde blanco suave
    label    = rgba(170, 170, 170, 255), -- Etiquetas en gris claro
    val      = rgba(255, 255, 255, 255), -- Valores normales en blanco
    dot      = rgba(255, 255, 255, 220), -- Punto indicador blanco
    good     = rgba(110, 225, 120, 255), -- Verde (buen ping / 0 loss)
    warn     = rgba(255, 210, 80,  255), -- Amarillo (ping medio)
    bad      = rgba(255, 90,  90,  255), -- Rojo (lag / choke / loss)
}

-- =========================================================================
-- ESTADO Y CONTROL DE ARRASTRE
-- =========================================================================
local drag    = { on = false, ox = 0, oy = 0, sx = 0, sy = 0, moved = false }
local mb_prev = false
local last_update = 0

local cached = {
    fps        = 0,
    tickrate   = 0,
    map        = "Menu",
    server     = "Local / Menu",
    ping_ms    = 0,
    loss_pct   = 0,
    choke_pct  = 0,
    in_rate    = 0,
    out_rate   = 0,
    conn_time  = "00:00:00",
}

local function format_time(seconds)
    if seconds <= 0 then return "00:00:00" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

-- =========================================================================
-- RECOLECCION DE METRICAS
-- =========================================================================
local function update_stats()
    cached.fps = math.floor(client.get_fps and client.get_fps() or 0)

    pcall(function()
        local ipt = GlobalVars.interval_per_tick()
        if ipt and ipt > 0 then
            cached.tickrate = math.floor((1.0 / ipt) + 0.5)
        end
    end)

    if not EngineClient.IsConnected() then
        cached.map       = "Menu"
        cached.server    = "No conectado"
        cached.ping_ms   = 0
        cached.loss_pct  = 0
        cached.choke_pct = 0
        cached.in_rate   = 0
        cached.out_rate  = 0
        cached.conn_time = "00:00:00"
        return
    end

    local map = EngineClient.GetLevelNameShort()
    cached.map = (map and map ~= "") and map or "Cargando..."

    local nc = EngineClient.GetNetChannelInfo()
    if nc and not nc:IsNull() then
        cached.server    = nc:GetAddress() or "Desconocido"
        cached.ping_ms   = math.floor((nc:GetAvgLatency(1) or 0) * 1000 + 0.5)
        cached.loss_pct  = (nc:GetAvgLoss(0) or 0) * 100
        cached.choke_pct = (nc:GetAvgChoke(0) or 0) * 100
        cached.in_rate   = (nc:GetAvgData(1) or 0) / 1024
        cached.out_rate  = (nc:GetAvgData(0) or 0) / 1024
        cached.conn_time = format_time(nc:GetTimeConnected() or 0)
    end
end

-- =========================================================================
-- RENDER (IMGUI DRAWLIST)
-- =========================================================================
local function draw()
    local now = os.clock()
    if now - last_update > 0.3 then
        update_stats()
        last_update = now
    end

    local dl = imgui.get_foreground_draw_list()
    local mx, my = imgui.GetMousePos()
    local mb = imgui.IsMouseDown(0)

    local just_dn = mb and not mb_prev
    local just_up = not mb and mb_prev
    mb_prev = mb

    local px, py = CFG.x, CFG.y

    -- Arrastre con el raton en el encabezado
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

    -- Filas de estadisticas a mostrar
    -- Color dinamico de ping segun intensidad
    local ping_col = C.good
    if cached.ping_ms > 120 then
        ping_col = C.bad
    elseif cached.ping_ms > 60 then
        ping_col = C.warn
    end

    local loss_col = (cached.loss_pct > 0 or cached.choke_pct > 0) and C.bad or C.good

    local rows = {
        { label = "Servidor",     val = cached.server,                                                 col = C.val },
        { label = "FPS / Tick",   val = string.format("%d fps | %dtick", cached.fps, cached.tickrate), col = C.val },
        { label = "Latencia",     val = string.format("%d ms", cached.ping_ms),                        col = ping_col },
        { label = "Loss / Choke", val = string.format("%.1f%% / %.1f%%", cached.loss_pct, cached.choke_pct), col = loss_col },
        { label = "Trafico",      val = string.format("%.1f in | %.1f out (KB/s)", cached.in_rate, cached.out_rate), col = C.val },
        { label = "Mapa",         val = cached.map,                                                    col = C.val },
        { label = "Sesion",       val = cached.conn_time,                                              col = C.val },
    }

    local total_rows_h = #rows * CFG.row_h + (#rows - 1) * CFG.gap
    local panel_h = CFG.hdr_h + CFG.pad_y * 2 + total_rows_h

    -- Fondo principal negro ahumado
    dl:add_rect_filled(px, py, px + CFG.w, py + panel_h, c(C.bg, CFG.rounding))

    -- Encabezado con esquinas redondeadas
    dl:add_rect_filled(px, py, px + CFG.w, py + CFG.hdr_h, c(C.hdr, CFG.rounding))
    local half = math.ceil(CFG.rounding)
    dl:add_rect_filled(px, py + CFG.hdr_h - half, px + CFG.w, py + CFG.hdr_h, c(C.hdr, 0))
    dl:add_line(px + 6, py + CFG.hdr_h, px + CFG.w - 6, py + CFG.hdr_h, c(C.sep, 1.0))

    -- Titulo "Network & Session"
    local title = "Network & Session"
    local tw    = imgui.CalcTextSize(title)
    dl:add_text(px + (CFG.w - tw) * 0.5, py + (CFG.hdr_h - 13) * 0.5, c(C.hdr_txt, title))

    -- Dibujar filas en dos columnas (Etiqueta <---> Valor)
    local cy = py + CFG.hdr_h + CFG.pad_y
    for _, r in ipairs(rows) do
        local dot_x = px + CFG.pad_x + 4
        local dot_y = cy + CFG.row_h * 0.5
        local ty    = cy + (CFG.row_h - 13) * 0.5

        -- Punto indicador blanco
        dl:add_circle_filled(dot_x, dot_y, 2.5, c(C.dot))

        -- Etiqueta
        dl:add_text(dot_x + 8, ty, c(C.label, r.label))

        -- Valor alineado a la derecha
        local vw = imgui.CalcTextSize(r.val)
        local vx = px + CFG.w - CFG.pad_x - vw
        dl:add_text(vx, ty, c(r.col, r.val))

        cy = cy + CFG.row_h + CFG.gap
    end

    -- Borde exterior blanco suave
    dl:add_rect(px, py, px + CFG.w, py + panel_h, c(C.border, 1.0, CFG.rounding))
end

function on_end_scene()
    if _G.echidna_netoverlay_instance ~= INSTANCE then return end
    pcall(draw)
end

function on_unload()
    drag.on = false
    mb_prev = false
    client.print("[NetworkOverlay] Descargado.")
end

client.print("[NetworkOverlay] Cargado — Mismo diseno Black & White.")






