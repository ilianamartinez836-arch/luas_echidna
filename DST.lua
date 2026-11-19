-- Name Tools & Silent Stealer — Echidna (L4D2)
-- Menú con Presets de Símbolos (Horizontal/Vertical) y Silent Name Steal
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_nametools_instance = INSTANCE

-- =========================================================================
-- CONSTANTES DEL MOTOR
-- =========================================================================
local MAX_NAME_LENGTH              = 31
local MAX_VERTICAL_CHARS           = 15
local COLOR_ESC                    = "\003"          -- Prefijo blanco / anti-duplicado
local ZERO_WIDTH                   = "\226\128\139"  -- U+200B Zero-Width Space

-- =========================================================================
-- PRESETS DE SÍMBOLOS GEOMÉTRICOS Y BLOQUES
-- =========================================================================
local PRESETS = {
    { label = "Solid Full Block",       text = string.rep("█", 15) },
    { label = "Dark Shade Block",       text = string.rep("▓", 15) },
    { label = "Medium Shade Block",     text = string.rep("▒", 15) },
    { label = "Light Shade Block",      text = string.rep("░", 15) },
    { label = "Solid Square Line",      text = string.rep("■", 15) },
    { label = "Heavy Vertical Block",   text = string.rep("▉", 15) },
    { label = "Block Wave (Asc/Desc)",  text = "▂▃▄▅▆▇██▇▆▅▄▃▂" },
    { label = "4-Step Gradient",        text = "█▓▒░█▓▒░█▓▒░" },
    { label = "Centered Wave",          text = "░▒▓██▓▒░░▒▓██▓▒░" },
}

-- =========================================================================
-- CONFIGURACIÓN DEL MENÚ
-- =========================================================================
local cfg = {
    custom_input  = "Player",
    is_vertical   = false,
    use_white     = true,
    preset_idx    = 1,
    target_player = 1,
}

-- =========================================================================
-- ESTADO DEL SILENT STEAL
-- =========================================================================
local steal_state = {
    active   = false,
    target   = "",
    deadline = 0,
    due_at   = 0,
}

local function log(msg)
    pcall(client.print, "[NameTools] " .. tostring(msg))
end

-- =========================================================================
-- HELPERS DE TEXTO Y UTF-8
-- =========================================================================
local function sanitize_name(name)
    name = tostring(name or ""):gsub("[%z\1-\31\127]", "")
    local invis = {
        ZERO_WIDTH, COLOR_ESC,
        "\226\128\139", "\226\128\140", "\226\128\141", "\226\128\142", "\226\128\143", "\239\187\191",
    }
    for i = 1, #invis do
        name = name:gsub(invis[i], "")
    end
    return name:match("^%s*(.-)%s*$") or ""
end

local function get_utf8_chars(str)
    local chars = {}
    for ch in tostring(str or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        chars[#chars + 1] = ch
    end
    return chars
end

-- =========================================================================
-- CONSTRUCCIÓN DE NOMBRES (HORIZONTAL / VERTICAL)
-- =========================================================================
local function build_horizontal(name, use_white_prefix)
    local clean = sanitize_name(name)
    if clean == "" then return nil end

    local prefix = use_white_prefix and COLOR_ESC or ""
    local out = prefix
    local chars = get_utf8_chars(clean)

    for _, ch in ipairs(chars) do
        if #out + #ch <= MAX_NAME_LENGTH then
            out = out .. ch
        else
            break
        end
    end
    return out
end

local function build_vertical(name)
    local clean = sanitize_name(name)
    local chars = get_utf8_chars(clean)
    if #chars == 0 then return nil end

    local count = math.min(#chars, MAX_VERTICAL_CHARS)

    while count > 0 do
        local lines = {}
        if count <= 7 then
            for i = 1, count do lines[#lines + 1] = chars[i] end
        else
            for i = 1, 6 do lines[#lines + 1] = chars[i] end
            local rest = {}
            for i = 7, count do rest[#rest + 1] = chars[i] end
            lines[#lines + 1] = table.concat(rest)
        end

        local leading = 1 + math.abs(count - 7)
        local payload = string.rep("\r", leading) .. table.concat(lines, "\r")

        if #payload <= MAX_NAME_LENGTH then
            return payload
        end
        count = count - 1
    end
    return nil
end

local function exec_setinfo_name(payload)
    if not payload or payload == "" then return end
    payload = tostring(payload):gsub('"', "")
    pcall(EngineClient.ClientCmd, string.format('setinfo name "%s"', payload))
end

-- =========================================================================
-- LOGICA DEL SILENT STEALER
-- =========================================================================
local function get_my_name()
    local lp_idx = EngineClient.GetLocalPlayer()
    if not lp_idx or lp_idx <= 0 then return "" end
    local info = EngineClient.GetPlayerInfo(lp_idx)
    return info and info:name() or ""
end

local function start_silent_steal(raw_target)
    local clean_target = sanitize_name(raw_target)
    if clean_target == "" or not EngineClient.IsInGame() then return end

    steal_state.active   = true
    steal_state.target   = clean_target
    steal_state.deadline = os.clock() + 2.5
    steal_state.due_at   = 0

    -- Construir nombre clonado con prefijo invisible para evitar el (1)
    local spoofed = ZERO_WIDTH .. clean_target
    if #spoofed > MAX_NAME_LENGTH then
        spoofed = spoofed:sub(1, MAX_NAME_LENGTH)
    end

    exec_setinfo_name(spoofed)
    log("Robando nombre de: " .. clean_target)
end

local function process_silent_steal()
    if not steal_state.active or not EngineClient.IsInGame() then return end

    local now = os.clock()

    -- Paso 2: Si el servidor ya confirmó el cambio, enviar los 100 \r al chat para ocultar el aviso
    if steal_state.due_at > 0 then
        if now >= steal_state.due_at then
            pcall(EngineClient.ClientCmd, string.format('say "%s"', string.rep("\r", 100)))
            log("Limpieza de chat completada. Robo finalizado.")
            steal_state.active = false
            steal_state.due_at = 0
        end
        return
    end

    -- Paso 1: Esperar a que el nombre local coincida con el objetivo
    local current_name = sanitize_name(get_my_name())
    if current_name == steal_state.target then
        steal_state.due_at = now + 0.05
    elseif now >= steal_state.deadline then
        log("Tiempo de espera agotado para la confirmación del nombre.")
        steal_state.active = false
    end
end

-- Ejecutar el vigilante de robo cada frame
function on_create_move(cmd, lp)
    if _G.echidna_nametools_instance ~= INSTANCE then return end
    process_silent_steal()
end

-- =========================================================================
-- LISTA DE JUGADORES PARA EL STEALER
-- =========================================================================
local function get_player_list()
    local players = {}
    if not EngineClient.IsInGame() then return players end

    local my_idx = EngineClient.GetLocalPlayer()
    local max_clients = 32
    pcall(function() max_clients = EngineClient.GetMaxClients() or 32 end)

    for i = 1, max_clients do
        if i ~= my_idx then
            local info = EngineClient.GetPlayerInfo(i)
            if info and info:name() ~= "" and info:name() ~= "unknown" then
                players[#players + 1] = {
                    idx  = i,
                    name = info:name(),
                }
            end
        end
    end
    return players
end

-- =========================================================================
-- MENÚ EN ECHIDNA (PESTAÑA 'Name Tools')
-- =========================================================================
pcall(function()
    menu.add_main_tab("N", "Name Tools", function()
        pcall(imgui.Spacing)
        pcall(imgui.TextColored, 0.7, 0.85, 1.0, 1.0, "Name Tools & Silent Stealer")
        pcall(imgui.Separator)
        pcall(imgui.Spacing)

        -- 1. Configuración de Nombre / Formato
        pcall(imgui.Text, "Configuracion de Formato:")
        local _, nv = pcall(imgui.Checkbox, "Modo Vertical (Cascada con \\r)##fmt_v", cfg.is_vertical)
        if nv ~= nil then cfg.is_vertical = nv end

        if not cfg.is_vertical then
            local _, nw = pcall(imgui.Checkbox, "Color Blanco (Anti-duplicate \\003)##fmt_w", cfg.use_white)
            if nw ~= nil then cfg.use_white = nw end
        else
            pcall(imgui.TextDisabled("• Color blanco deshabilitado en vertical (usa saltos \\r)."))
        end

        pcall(imgui.Spacing)
        pcall(imgui.Separator)

        -- 2. Presets de Símbolos
        pcall(imgui.TextColored, 0.8, 0.8, 0.8, 1.0, "Presets de Simbolos:")
        local current_preset_label = PRESETS[cfg.preset_idx] and PRESETS[cfg.preset_idx].label or "Select Preset"
        if imgui.BeginCombo("##preset_picker", current_preset_label) then
            for i, p in ipairs(PRESETS) do
                if imgui.Selectable(p.label .. "##pr_" .. i, i == cfg.preset_idx) then
                    cfg.preset_idx = i
                end
            end
            imgui.EndCombo()
        end

        pcall(imgui.SameLine)
        if imgui.Button("Aplicar Preset##apply_pr", 110, 20) then
            local p_text = PRESETS[cfg.preset_idx].text
            local payload = cfg.is_vertical and build_vertical(p_text) or build_horizontal(p_text, cfg.use_white)
            exec_setinfo_name(payload)
            log("Preset aplicado: " .. PRESETS[cfg.preset_idx].label)
        end

        pcall(imgui.Spacing)
        pcall(imgui.Separator)

        -- 3. Texto Personalizado
        pcall(imgui.TextColored, 0.8, 0.8, 0.8, 1.0, "Nombre Personalizado:")
        local _, in_text = pcall(imgui.InputText, "##custom_name_input", cfg.custom_input)
        if in_text and in_text ~= "" then cfg.custom_input = in_text end

        pcall(imgui.SameLine)
        if imgui.Button("Aplicar Nombre##apply_custom", 110, 20) then
            local payload = cfg.is_vertical and build_vertical(cfg.custom_input) or build_horizontal(cfg.custom_input, cfg.use_white)
            exec_setinfo_name(payload)
            log("Nombre personalizado aplicado.")
        end

        pcall(imgui.Spacing)
        pcall(imgui.Separator)

        -- 4. Silent Name Steal
        pcall(imgui.TextColored, 1.0, 0.8, 0.3, 1.0, "Silent Name Steal:")
        local players = get_player_list()

        if #players > 0 then
            cfg.target_player = math.max(1, math.min(cfg.target_player, #players))
            local target_label = players[cfg.target_player].name

            if imgui.BeginCombo("##player_steal_combo", target_label) then
                for i, p in ipairs(players) do
                    if imgui.Selectable(string.format("[%d] %s", p.idx, p.name), i == cfg.target_player) then
                        cfg.target_player = i
                    end
                end
                imgui.EndCombo()
            end

            pcall(imgui.SameLine)
            local btn_text = steal_state.active and "Robando...##st_btn" or "Steal##st_btn"
            if imgui.Button(btn_text, 80, 20) and not steal_state.active then
                start_silent_steal(players[cfg.target_player].name)
            end
        else
            pcall(imgui.TextDisabled("No hay otros jugadores en la partida."))
        end

        pcall(imgui.Spacing)
        pcall(imgui.Separator)
        pcall(imgui.TextDisabled("Payload maximo respetado: 31 bytes."))
    end)
end)

function on_unload()
    steal_state.active = false
    client.print("[NameTools] Descargado.")
end

client.print("[NameTools] Cargado — Pestaña 'Name Tools' disponible en el menú.")
