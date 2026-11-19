-- Tank Lerp Switcher (Echidna L4D2)
-- Manten presionado MOUSE4 siendo Tank para golpear con 0.5 de lerp
local ffi = require("ffi")

pcall(ffi.cdef, [[
    short GetAsyncKeyState(int vKey);
]])

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local VK_MOUSE4   = 0x05        -- Boton lateral MOUSE4 (XBUTTON1)
local HIGH_LERP   = 0.5         -- Lerp alto para el hit
local IN_ATTACK   = 1           -- Bit de ataque (golpe)

-- =========================================================================
-- CONVAR Y ESTADO
-- =========================================================================
local cv_interp = Cvars.FindVar("cl_interp")
local default_interp = 0.007813

if cv_interp then
    local current = cv_interp:GetFloat()
    if current and current > 0 then
        default_interp = current
    end
end

local function set_interp(val)
    if cv_interp then
        cv_interp:SetFloat(val)
    end
    -- Respaldo directo al motor
    pcall(EngineClient.ClientCmd, string.format("cl_interp %f", val))
end

local is_holding_prev = false

local function is_key_down(vk)
    return bit.band(ffi.C.GetAsyncKeyState(vk), 0x8000) ~= 0
end

-- =========================================================================
-- LOGICA EN CREATEMOVE
-- =========================================================================
function on_create_move(cmd, lp)
    if not lp or not lp:is_alive() then return end
    if not EngineClient.IsInGame() then return end

    -- Solo cuando seamos Tank (Team 3 = Infected, Zombie Class 8 = Tank)
    local team = lp:get_team()
    local z_class = lp:get_zombie_class()

    if team ~= 3 or z_class ~= 8 then
        if is_holding_prev then
            set_interp(default_interp)
            is_holding_prev = false
        end
        return
    end

    local is_holding = is_key_down(VK_MOUSE4)

    if is_holding and not is_holding_prev then
        -- Al presionar MOUSE4: subir lerp a 0.5 y lanzar el golpe
        set_interp(HIGH_LERP)
        cmd:add_button(IN_ATTACK)

    elseif not is_holding and is_holding_prev then
        -- Al soltar MOUSE4: restaurar lerp bajo habitual
        set_interp(default_interp)
    end

    is_holding_prev = is_holding
end

-- =========================================================================
-- DESCARGA Y RESTAURACION
-- =========================================================================
function on_unload()
    set_interp(default_interp)
    client.print(string.format("[Tank Lerp] Restaurado lerp original: %f", default_interp))
end

client.print(string.format("[Tank Lerp] Cargado — Manten MOUSE4 siendo Tank (Lerp base: %f)", default_interp))

