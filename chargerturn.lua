-- Charger Turn + Infinite Carry (Echidna L4D2)
-- Sin menu, directo

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
-- false = Solo Charger Turn (girar libremente con el raton)
-- true  = Charger Turn + Carga Infinita (no se detiene hasta chocar pared)
local ENABLE_INFINITE_CARRY = false
local SEQ_SHIFT_AMOUNT      = 2000

-- =========================================================================
-- 1. CHARGER TURN (PARCHE DE MEMORIA EN CLIENT.DLL)
-- =========================================================================
local ffi = require("ffi")

pcall(ffi.cdef, [[
    int VirtualProtect(void* lpAddress, size_t dwSize, uint32_t flNewProtect, uint32_t* lpflOldProtect);
]])

local PAGE_EXECUTE_READWRITE = 0x40
local patch_addr = memory.find_pattern("client.dll", "74 2D D9")
local original_byte = nil

local function patch_memory(addr, byte)
    if not addr or addr == 0 then return end
    local old = ffi.new("uint32_t[1]")
    if ffi.C.VirtualProtect(ffi.cast("void*", addr), 1, PAGE_EXECUTE_READWRITE, old) ~= 0 then
        ffi.cast("uint8_t*", addr)[0] = byte
        ffi.C.VirtualProtect(ffi.cast("void*", addr), 1, old[0], old)
    end
end

if patch_addr and patch_addr > 0 then
    original_byte = ffi.cast("uint8_t*", patch_addr)[0]
    patch_memory(patch_addr, 0xEB) -- 74 (JE) -> EB (JMP): quita el bloqueo de giro
    client.print("[ChargerTurn] Parche de giro activado.")
else
    client.print("[ChargerTurn] Error: no se encontro la firma en client.dll.")
end

-- =========================================================================
-- 2. CARGA INFINITA (SEQUENCE SHIFTING VIA INETCHANNEL)
-- =========================================================================
local is_carrying = false
local event_ids   = {}

local function monitor_carry_events(ev)
    if not ENABLE_INFINITE_CARRY then
        is_carrying = false
        return
    end

    local ename = ev:GetName()
    local userid = ev:GetInt("userid")
    local local_idx = EngineClient.GetLocalPlayer()
    local sender_idx = EngineClient.GetPlayerForUserID(userid)

    if sender_idx ~= local_idx then return end

    if ename == "charger_carry_start" then
        is_carrying = true
    elseif ename == "charger_carry_end" or ename == "charger_impact" or 
           ename == "player_death" or ename == "player_first_spawn" or
           ename == "round_start" or ename == "round_end" then
        is_carrying = false
    end
end

-- Registrar eventos solo para la carga infinita
local events_to_listen = {
    "charger_carry_start",
    "charger_carry_end",
    "charger_impact",
    "player_death",
    "player_first_spawn",
    "round_start",
    "round_end"
}

for _, name in ipairs(events_to_listen) do
    local id = events.add_listener(name, monitor_carry_events)
    if id then
        event_ids[#event_ids + 1] = { name = name, id = id }
    end
end

-- Manipulacion en CreateMove
function on_create_move(cmd, lp)
    if not ENABLE_INFINITE_CARRY or not is_carrying then return end
    if not EngineClient.IsInGame() then
        is_carrying = false
        return
    end

    -- Seguridad: si ya no somos Charger o morimos, apagar
    if lp then
        local p = lp:as("CTerrorPlayer")
        if p and (not p:is_alive() or p:get_zombie_class() ~= 6) then
            is_carrying = false
            return
        end
    end

    -- Congelar el temporizador de la carga desfasando secuencias
    local nc = EngineClient.GetNetChannelInfo()
    if nc and not nc:IsNull() then
        local cur_seq = nc:m_nOutSequenceNr()
        if cur_seq then
            nc:SetOutSequenceNr(cur_seq + SEQ_SHIFT_AMOUNT)
        end
    end
end

-- =========================================================================
-- DESCARGA Y RESTAURACION
-- =========================================================================
function on_unload()
    -- Restaurar byte original de giro en el cliente
    if patch_addr and patch_addr > 0 and original_byte ~= nil then
        patch_memory(patch_addr, original_byte)
        client.print("[ChargerTurn] Parche de memoria restaurado.")
    end

    -- Remover listeners
    for _, ev in ipairs(event_ids) do
        if ev.id then
            pcall(events.remove_listener, ev.name, ev.id)
        end
    end

    memory.restore_all()
    client.print("[ChargerTurn] Descargado.")
end




