-- UI Layout & Design Showcase — Echidna (L4D2)
-- Prueba de estructuras, tarjetas, columnas y selectores modernos
local ffi = require("ffi")

pcall(ffi.cdef, [[
    short GetAsyncKeyState(int vKey);
]])

-- =========================================================================
-- ESTADO DE PRUEBA
-- =========================================================================
local ui_cfg = {
    master_switch = true,
    exploit_mode  = 1,     -- 1 = Static Ghost (Stuck) | 2 = Mobile Jitter (Tirones)
    key_mode      = false, -- false = HOLD | true = TOGGLE
    current_key   = 0x43,  -- Tecla 'C'
    turbo_power   = 135,
    godmode_hp    = true,
}

local waiting_for_key = false

-- Mapeo de teclas limpio
local KEY_NAMES = {
    [0x01]="MOUSE1", [0x02]="MOUSE2", [0x04]="MOUSE3", [0x05]="MOUSE4", [0x06]="MOUSE5",
    [0x20]="SPACE",  [0x10]="SHIFT",  [0x11]="CTRL",   [0x12]="ALT",   [0x1B]="ESC",
}
for i = 0x41, 0x5A do KEY_NAMES[i] = string.char(i) end
for i = 0x30, 0x39 do KEY_NAMES[i] = string.char(i) end

local function get_key_name(vk)
    return KEY_NAMES[vk] or ("0x" .. string.format("%X", vk))
end

local function is_key_held(vk)
    if not vk or vk == 0 then return false end
    return bit.band(ffi.C.GetAsyncKeyState(vk), 0x8000) ~= 0
end

-- Captura de teclado infalible
function on_key_down(key)
    if waiting_for_key then
        if key == 0x1B then
            waiting_for_key = false
            return
        end
        ui_cfg.current_key = key
        waiting_for_key = false
    end
end

function on_end_scene()
    if waiting_for_key then
        for vk = 0x02, 0x06 do
            if vk ~= 0x01 and is_key_held(vk) then
                ui_cfg.current_key = vk
                waiting_for_key = false
                break
            end
        end
    end
end

-- =========================================================================
-- MENU SHOWCASE EN ECHIDNA (PESTAÑA '☠ Layout Test')
-- =========================================================================
pcall(function()
    menu.add_main_tab("X", "Layout Test", function()
        pcall(function()
            if imgui.Spacing then imgui.Spacing() end

            -- 1. Encabezado de categoría superior
            imgui.TextColored(0.35, 0.85, 1.0, 1.0, "SUPREMACY ENGINE")
            imgui.SameLine()
            imgui.TextDisabled("// Private Exploit Architecture")
            if imgui.Separator then imgui.Separator() end
            if imgui.Spacing then imgui.Spacing() end

            -- 2. DISTRIBUCIÓN EN 2 COLUMNAS (IZQUIERDA: CONTROLES | DERECHA: ESTADO)
            -- Tarjeta Izquierda: Ajustes del Exploit
            imgui.BeginChild("##left_panel", 280, 290, true)
                imgui.TextColored(0.8, 0.8, 0.8, 1.0, "Control & Configuracion")
                imgui.Separator()
                imgui.Spacing()

                -- Master Enable
                local v_master = imgui.Checkbox("Master Enable##ui_master", ui_cfg.master_switch)
                if v_master ~= nil then ui_cfg.master_switch = v_master end

                local v_hp = imgui.Checkbox("Godmode HP Buffer Lock##ui_hp", ui_cfg.godmode_hp)
                if v_hp ~= nil then ui_cfg.godmode_hp = v_hp end

                imgui.Spacing()
                imgui.Separator()
                imgui.Text("Modo de Desync:")
                imgui.Spacing()

                -- Selector de Modo estilo Botones Horizontales (Píldoras)
                local m1_active = (ui_cfg.exploit_mode == 1)
                local m2_active = (ui_cfg.exploit_mode == 2)

                if m1_active then
                    imgui.PushStyleColor(imgui.ImGuiCol_Button, 0.20, 0.55, 0.85, 0.90)
                else
                    imgui.PushStyleColor(imgui.ImGuiCol_Button, 0.12, 0.14, 0.18, 0.80)
                end
                if imgui.Button("1. Static Stuck##mode_1", 125, 24) then
                    ui_cfg.exploit_mode = 1
                end
                imgui.PopStyleColor()

                imgui.SameLine()

                if m2_active then
                    imgui.PushStyleColor(imgui.ImGuiCol_Button, 0.20, 0.55, 0.85, 0.90)
                else
                    imgui.PushStyleColor(imgui.ImGuiCol_Button, 0.12, 0.14, 0.18, 0.80)
                end
                if imgui.Button("2. Mobile Jitter##mode_2", 125, 24) then
                    ui_cfg.exploit_mode = 2
                end
                imgui.PopStyleColor()

                imgui.Spacing()
                imgui.Separator()

                -- Slider de Choke
                local nv = imgui.SliderInt("Turbo Choke##ui_val", ui_cfg.turbo_power, 45, 145)
                if nv ~= nil then ui_cfg.turbo_power = nv end

                imgui.Spacing()

                -- Keybinder interactivo y Tipo de activación
                local key_str = waiting_for_key and "[ Press Key... ]##ui_k" or string.format("Tecla: [ %s ]##ui_k", get_key_name(ui_cfg.current_key))
                if imgui.Button(key_str, 130, 24) then
                    waiting_for_key = not waiting_for_key
                end

                imgui.SameLine()

                local type_str = ui_cfg.key_mode and "Tipo: [ TOGGLE ]##ui_t" or "Tipo: [ HOLD ]##ui_t"
                if imgui.Button(type_str, 120, 24) then
                    ui_cfg.key_mode = not ui_cfg.key_mode
                end

            imgui.EndChild()

            imgui.SameLine()

            -- Tarjeta Derecha: Telemetría y Diagnóstico en Vivo
            imgui.BeginChild("##right_panel", 260, 290, true)
                imgui.TextColored(0.9, 0.75, 0.2, 1.0, "Telemetria en Tiempo Real")
                imgui.Separator()
                imgui.Spacing()

                -- Indicador del estado de la tecla asignada
                local holding = is_key_held(ui_cfg.current_key)
                if holding then
                    imgui.TextColored(0.2, 1.0, 0.3, 1.0, string.format("TECLA: >>> [ %s ACTIVA ] <<<", get_key_name(ui_cfg.current_key)))
                else
                    imgui.TextColored(0.5, 0.5, 0.5, 1.0, string.format("TECLA: [ %s INACTIVA ]", get_key_name(ui_cfg.current_key)))
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()

                imgui.Text("Resumen del Modo Seleccionado:")
                if ui_cfg.exploit_mode == 1 then
                    imgui.TextColored(0.4, 0.8, 1.0, 1.0, "• Static Ghost (Stuck):")
                    imgui.TextDisabled("Hitbox anclada en el suelo.\nInmortalidad estatica total.\nTe teletransportas al soltar.")
                else
                    imgui.TextColored(0.3, 1.0, 0.5, 1.0, "• Mobile Jitter (Tirones):")
                    imgui.TextDisabled("Avanzas caminando a saltos.\nDesync dinamico en carrera.\nHitbox parpadea en movimiento.")
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()

                imgui.Text("Capa de Red:")
                imgui.TextColored(0.3, 1.0, 0.3, 1.0, "• Engine NOP: DESBLOQUEADO")
                imgui.TextColored(0.3, 1.0, 0.3, 1.0, "• NetChannel Spoof: -1 / 255")
                imgui.TextColored(0.3, 1.0, 0.3, 1.0, "• Single Owner: ACTIVO")

            imgui.EndChild()
        end)
    end)
end)

function on_unload()
    waiting_for_key = false
    client.print("[LayoutShowcase] Descargado.")
end

client.print("[LayoutShowcase] Cargado — Abre la pestaña '☠ Layout Test' para ver el diseño.")

