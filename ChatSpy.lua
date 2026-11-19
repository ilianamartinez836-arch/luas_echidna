-- ChatSpy — Echidna (L4D2)
-- Solo chat privado del enemigo, sin duplicar chat publico, sin comillas
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_chatspy_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    void* GetProcAddress(void* hModule, const char* lpProcName);
    typedef struct {
        char __pad00[0x8];
        char name[32];
        int userid;
        char guid[33];
        unsigned int friendsid;
        char __pad01[0x150];
    } player_info_t;
]])

local client_base = ffi.C.GetModuleHandleA("client.dll")
local chatPtrAddr = ffi.cast("void***", ffi.cast("uintptr_t", client_base) + 0x757920)
local c_hud_chat = chatPtrAddr and chatPtrAddr[0] or nil
local ffi_print_chat = nil

if c_hud_chat ~= nil and ffi.cast("uintptr_t", c_hud_chat) > 0x10000 then
    local vtbl = ffi.cast("void***", c_hud_chat)[0]
    if vtbl and vtbl[23] ~= nil then
        ffi_print_chat = ffi.cast("void(__cdecl*)(void*, int, int, const char*, ...)", vtbl[23])
    end
end

local function PrintChat(msg)
    if not c_hud_chat or not ffi_print_chat then return end
    pcall(function()
        ffi_print_chat(c_hud_chat, 0, 0, " " .. tostring(msg))
    end)
end

local function get_engine_client()
    local engine_mod = ffi.C.GetModuleHandleA("engine.dll")
    if engine_mod == nil then return nil end
    local create_interface = ffi.cast(
        "void* (__cdecl*)(const char*, int*)",
        ffi.C.GetProcAddress(engine_mod, "CreateInterface")
    )
    if create_interface == nil then return nil end
    return create_interface("VEngineClient013", nil)
end

local engine_client = get_engine_client()
local vfunc_GetPlayerInfo = nil
if engine_client then
    local engine_vtbl = ffi.cast("void***", engine_client)
    vfunc_GetPlayerInfo = ffi.cast(
        "bool(__thiscall*)(void*, int, player_info_t*)",
        engine_vtbl[0][8]
    )
end

local function player_name_by_index(idx)
    if not idx or idx <= 0 or not vfunc_GetPlayerInfo then return "Unknown" end
    local info = ffi.new("player_info_t[1]")
    local ok, ret = pcall(function() return vfunc_GetPlayerInfo(engine_client, idx, info) end)
    if not ok or not ret then return "Unknown" end
    local name = ffi.string(info[0].name)
    if not name or name == "" then return "Unknown" end
    return name
end

local function userid_to_index(userid)
    if not userid or userid == 0 then return 0 end
    local ok, idx = pcall(EngineClient.GetPlayerForUserID, userid)
    if ok and type(idx) == "number" and idx > 0 then return idx end
    if not vfunc_GetPlayerInfo then return 0 end
    local maxc = 32
    pcall(function()
        local m = EngineClient.GetMaxClients()
        if type(m) == "number" and m > 0 then maxc = m end
    end)
    for i = 1, maxc do
        local info = ffi.new("player_info_t[1]")
        local okc, ret = pcall(function() return vfunc_GetPlayerInfo(engine_client, i, info) end)
        if okc and ret and info[0].userid == userid then
            return i
        end
    end
    return 0
end

local function entity_by_index(idx)
    if not idx or idx <= 0 then return nil end
    local ent
    pcall(function() ent = ClientEntityList.GetClientEntity(idx) end)
    return ent
end

local function as_player(ent)
    if not ent then return nil end
    local p = ent
    pcall(function()
        if ent.as then
            local a = ent:as("CTerrorPlayer")
            if a then p = a end
        end
    end)
    return p
end

local function get_team_num(ent)
    if not ent then return 0 end
    local p = as_player(ent)
    local team = nil
    pcall(function() team = p:get_team() end)
    if team == 1 or team == 2 or team == 3 then return team end
    pcall(function() team = p:get_prop_int("DT_BaseEntity", "m_iTeamNum") end)
    if team == 1 or team == 2 or team == 3 then return team end
    pcall(function() team = p:get_prop_int("CTerrorPlayer", "m_iTeamNum") end)
    if team == 1 or team == 2 or team == 3 then return team end
    local zc = nil
    pcall(function() zc = p:get_zombie_class() end)
    if type(zc) == "number" then
        if zc >= 0 and zc <= 8 then return 3 end
        if zc == 9 then return 2 end
    end
    return 0
end

local function team_label(team)
    if team == 2 then return "(Survivor)"
    elseif team == 3 then return "(Infected)"
    end
    return "(Enemy)"
end

local function name_by_entityid(entityid)
    if not entityid or entityid <= 0 then return "Unknown" end
    local n = player_name_by_index(entityid)
    if n and n ~= "Unknown" then return n end
    return "Ent#" .. tostring(entityid)
end

local function local_team_and_idx()
    local idx = 0
    pcall(function() idx = EngineClient.GetLocalPlayer() or 0 end)
    return idx, get_team_num(entity_by_index(idx))
end

-- =========================================================================
-- DETECTOR DE CHAT PUBLICO NATIVO
-- =========================================================================
-- Cuando el motor muestra un mensaje en pantalla, lo registramos.
-- Si el mensaje ya salio de forma nativa, sabemos que es publico y no lo duplicamos.
local native_chat_msgs = {}
local chat_hook = nil

local cp_addr = memory.find_pattern("client.dll",
    "55 8B EC B8 E4 10 00 00 E8 ? ? ? ? A1 ? ? ? ? 33 C5 89 45 FC 8B 4D 14")

if cp_addr and cp_addr > 0 then
    pcall(function()
        chat_hook = hooks.create(cp_addr,
            "int(__cdecl*)(void*, int, int, const char*, const char*)",
            function(orig, ctx, player_ref, flags, fmt, msg)
                local cur_t = os.clock()
                local s1 = (fmt and ffi.cast("uintptr_t", fmt) > 0x10000) and ffi.string(fmt) or ""
                local s2 = (msg and ffi.cast("uintptr_t", msg) > 0x10000) and ffi.string(msg) or ""

                if s1 ~= "" then native_chat_msgs[s1] = cur_t end
                if s2 ~= "" then native_chat_msgs[s2] = cur_t end

                return orig(ctx, player_ref, flags, fmt, msg)
            end)
    end)
end

local function is_already_shown_natively(txt)
    local now = os.clock()
    for stored_txt, t in pairs(native_chat_msgs) do
        if (now - t) > 1.2 then
            native_chat_msgs[stored_txt] = nil
        elseif string.find(stored_txt, txt, 1, true) and (now - t) <= 0.8 then
            return true
        end
    end
    return false
end

-- Anti-duplicados por key
local last_key, last_t = "", 0
local function should_print(key)
    local now = os.clock()
    if key == last_key and (now - last_t) < 0.4 then return false end
    last_key, last_t = key, now
    return true
end

local function on_chat(ev)
    if not ev then return end
    if not EngineClient.IsInGame or not EngineClient.IsInGame() then return end

    local userid, text = 0, nil
    pcall(function() userid = ev:GetInt("userid") or 0 end)
    pcall(function() text = ev:GetString("text") end)
    if not text or text == "" then
        pcall(function() text = ev:GetString("message") end)
    end
    if not text or text == "" then return end

    local idx = userid_to_index(userid)
    if idx <= 0 then return end

    local local_idx, local_team = local_team_and_idx()
    if idx == local_idx then return end

    local team = get_team_num(entity_by_index(idx))

    -- Ignorar si es de nuestro propio equipo
    if local_team ~= 0 and team == local_team then return end

    -- Si el mensaje ya salio en el chat publico nativo del juego, NO duplicar
    if is_already_shown_natively(text) then
        return
    end

    local name = player_name_by_index(idx)
    if name == "Unknown" then name = name_by_entityid(idx) end

    local key = tostring(userid) .. "|" .. tostring(text)
    if not should_print(key) then return end

    -- Formato sin comillas: (Team) nombre : mensaje
    PrintChat(string.format("%s %s : %s", team_label(team), name, text))
end

local id_say = events.add_listener("player_say", on_chat)
local id_team = events.add_listener("player_say_team", on_chat)

client.print("[ChatSpy] Cargado (solo chat privado enemigo, sin duplicados).")

function on_unload()
    if chat_hook then
        pcall(function() chat_hook:destroy() end)
        chat_hook = nil
    end
    if id_say then
        pcall(events.remove_listener, "player_say", id_say)
    end
    if id_team then
        pcall(events.remove_listener, "player_say_team", id_team)
    end
    memory.restore_all()
    client.print("[ChatSpy] Descargado.")
end
