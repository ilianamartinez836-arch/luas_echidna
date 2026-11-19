-- CL_Move Extra Commands Injector (Prueba Pura de Saturación) — Echidna (L4D2)
-- Manten presionada la 'V' para bombear 14 llamadas extra por tick al servidor
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_clmove_pump_instance = INSTANCE

pcall(ffi.cdef, [[
    short GetAsyncKeyState(int vKey);
]])

local VK_V        = 0x56 -- Tecla 'V' (0x56)
local EXTRA_TICKS = 14   -- 14 llamadas extra por tick (techo del protocolo)

local function is_key_down(vk)
    return bit.band(ffi.C.GetAsyncKeyState(vk), 0x8000) ~= 0
end

function on_cl_move_pre()
    if _G.echidna_clmove_pump_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then
        client.set_extra_commands(0)
        return
    end

    -- Si mantienes la 'V', bombea 14 comandos extra al motor en cada frame
    if is_key_down(VK_V) then
        client.set_extra_commands(EXTRA_TICKS)
    else
        client.set_extra_commands(0)
    end
end

function on_unload()
    client.set_extra_commands(0)
    client.print("[CLMovePump] Descargado — Inyección reseteada a 0.")
end

client.print("[CLMovePump] Cargado — Manten 'V' para forzar 14 llamadas extra por frame.")
