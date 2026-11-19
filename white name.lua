-- Name Color Exploit (Heaven Port 1:1) — Echidna (L4D2)
-- Tecla FIN para aplicar el prefijo de color blanco y zero-width
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_heaven_name_instance = INSTANCE

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local MY_NAME = "卐卐卐卐卐卐卐卐卐卐卐卐" -- Cambia aqui el nombre que quieres que se aplique

-- Constantes exactas del script de Heaven:
local MAX_NAME_LENGTH = 31
local COLOR_ESC       = "\004"           -- Byte de color real de Heaven (Blanco / Neutro)
local ZERO_WIDTH      = "\226\128\139"   -- Byte zero-width U+200B (Anti-duplicado)

-- =========================================================================
-- LOGICA DE CONSTRUCCION (IDÉNTICA A HEAVEN)
-- =========================================================================
local function sanitize_name(name)
    name = tostring(name or "")
    name = name:gsub("[%z\1-\31\127]", "")
    local invis = {
        ZERO_WIDTH, COLOR_ESC,
        "\226\128\139", "\226\128\140", "\226\128\141", "\226\128\142", "\226\128\143",
        "\239\187\191",
    }
    for i = 1, #invis do
        name = name:gsub(invis[i], "")
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name
end

local function build_name(raw_name)
    local clean = sanitize_name(raw_name)
    if clean == "" then return nil end

    -- Ensamblado exacto de Heaven: ZERO_WIDTH + COLOR_ESC + NOMBRE
    local out = COLOR_ESC .. clean
    out = ZERO_WIDTH .. out

    -- Respetar el limite de 31 bytes del motor de Source
    if #out > MAX_NAME_LENGTH then
        out = out:sub(1, MAX_NAME_LENGTH)
    end

    return out
end

local function apply_name()
    local final_name = build_name(MY_NAME)
    if not final_name then return end

    -- Ejecucion limpia sin comillas internas
    final_name = tostring(final_name):gsub('"', "")
    pcall(function()
        EngineClient.ClientCmd('setinfo name "' .. final_name .. '"')
    end)

    client.print("[NameColor] Nombre aplicado con prefijo Heaven: " .. sanitize_name(MY_NAME))
end

-- =========================================================================
-- DETECCION DE LA TECLA "FIN" (0x23 = VK_END / 0x61 = Numpad 1)
-- =========================================================================
function on_key_down(key)
    if key == 0x23 or key == 0x61 then
        apply_name()
    end
end

function on_unload()
    client.print("[NameColor] Descargado.")
end

client.print("[NameColor] Cargado — Presiona FIN para aplicar el nombre blanco.")
