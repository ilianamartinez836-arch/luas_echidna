-- VoteSpy (Celeste [VOTE] Tag) — Echidna (L4D2)
-- Te muestra en tiempo real quién inició la votación y quién vota YES o NO
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_votespy_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
]])

-- =========================================================================
-- RESOLUCION DE CHUDCHAT PARA IMPRIMIR EN CHAT NATIVO
-- =========================================================================
local client_base = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("client.dll"))
local chat_ptr    = ffi.cast("void***", client_base + 0x757920)
local c_hud_chat  = chat_ptr and chat_ptr[0] or nil
local ffi_print_chat = nil

if c_hud_chat ~= nil and ffi.cast("uintptr_t", c_hud_chat) > 0x10000 then
    local vtbl = ffi.cast("void***", c_hud_chat)[0]
    if vtbl and vtbl[23] ~= nil then
        ffi_print_chat = ffi.cast("void(__cdecl*)(void*, int, int, const char*, ...)", vtbl[23])
    end
end

local function print_to_chat(msg)
    if not c_hud_chat or not ffi_print_chat then return end
    pcall(ffi_print_chat, c_hud_chat, 0, 0, msg)
end

-- =========================================================================
-- RESOLUCION DE NOMBRES DE JUGADORES
-- =========================================================================
local function get_player_name(ent_idx)
    if not ent_idx or ent_idx <= 0 then return "Unknown" end

    -- 1. Intentar por EngineClient
    local info = EngineClient.GetPlayerInfo(ent_idx)
    if info and info:name() ~= "" then
        return info:name()
    end

    -- 2. Intentar por ClientEntityList
    local ent = ClientEntityList.GetClientEntity(ent_idx)
    if ent and ent:is_valid() then
        local p = ent:as("CTerrorPlayer")
        if p and p.get_name and p:get_name() ~= "" then
            return p:get_name()
        end
    end

    return "Player#" .. tostring(ent_idx)
end

-- =========================================================================
-- LISTENERS DE VOTACION
-- =========================================================================
-- \x03 = Color Celeste / Azul claro (Source Engine)
-- \x01 = Color blanco / default para el resto del texto
local TAG = "\x03[VOTE]\x01 "

local ids = {}
local function add_ev(name, fn)
    local id = events.add_listener(name, function(ev)
        if _G.echidna_votespy_instance ~= INSTANCE then return end
        if not EngineClient.IsInGame() then return end
        fn(ev)
    end)
    if id then
        ids[#ids + 1] = { name = name, id = id }
    end
end

-- 1. Inicio de votación
add_ev("vote_started", function(ev)
    local issue     = ev:GetString("issue") or "?"
    local param     = ev:GetString("param1") or ""
    local initiator = ev:GetInt("initiator") or 0

    local detail = (param ~= "") and (issue .. " " .. param) or issue
    local name   = (initiator > 0) and get_player_name(initiator) or "Server"

    print_to_chat(string.format("%s%s started: %s", TAG, name, detail))
end)

-- 2. Voto YES
add_ev("vote_cast_yes", function(ev)
    local entityid = ev:GetInt("entityid") or 0
    if entityid <= 0 then return end

    print_to_chat(string.format("%s%s : YES", TAG, get_player_name(entityid)))
end)

-- 3. Voto NO
add_ev("vote_cast_no", function(ev)
    local entityid = ev:GetInt("entityid") or 0
    if entityid <= 0 then return end

    print_to_chat(string.format("%s%s : NO", TAG, get_player_name(entityid)))
end)

-- 4. Votación Aprobada (PASSED)
add_ev("vote_passed", function(ev)
    local detail = ev:GetString("details") or ev:GetString("issue") or ""
    if detail ~= "" then
        print_to_chat(string.format("%sPASSED: %s", TAG, detail))
    else
        print_to_chat(TAG .. "PASSED")
    end
end)

-- 5. Votación Rechazada (FAILED)
add_ev("vote_failed", function(ev)
    print_to_chat(TAG .. "FAILED")
end)

client.print("[VoteSpy] Loaded — [VOTE] tag in light blue.")

-- =========================================================================
-- DESCARGA SEGURA
-- =========================================================================
function on_unload()
    for _, ev in ipairs(ids) do
        if ev.id then
            pcall(events.remove_listener, ev.name, ev.id)
        end
    end
    client.print("[VoteSpy] Unloaded.")
end
