-- Kill Notifier + Consistency Bypass — Echidna
local ffi = require("ffi")

local FCVAR_CHEAT     = 16384
local FCVAR_PROTECTED = 32

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
local c_hud_chat = chatPtrAddr[0]
local ffi_print_chat = ffi.cast(
    "void(__cdecl*)(void*, int, int, const char*, ...)",
    ffi.cast("void***", c_hud_chat)[0][23]
)

local function PrintChat(msg, ent_idx)
    if not c_hud_chat or not ffi_print_chat then return end
    pcall(function()
        ffi_print_chat(c_hud_chat, ent_idx or 0, 0, " " .. tostring(msg))
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

-- team: get_team -> prop -> zombie_class (0-8 infected, 9 survivor en L4D2)
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

    pcall(function() team = p:get_prop_int("CBaseEntity", "m_iTeamNum") end)
    if team == 1 or team == 2 or team == 3 then return team end

    local zc = nil
    pcall(function() zc = p:get_zombie_class() end)
    if type(zc) == "number" then
        if zc >= 0 and zc <= 8 then return 3 end
        if zc == 9 then return 2 end
    end

    return 0
end
local function get_team_prefix(ent)
    local team = get_team_num(ent)
    if team == 3 then return ""
    elseif team == 2 then return ""
    elseif team == 1 then return ""
    end
    return "(Unknown) "
end
local function entity_by_index(idx)
    if not idx or idx <= 0 then return nil end
    local ent
    pcall(function() ent = ClientEntityList.GetClientEntity(idx) end)
    return ent
end

local function on_death(ev)
    if not ev then return end
    if not EngineClient.IsInGame or not EngineClient.IsInGame() then return end

    local userid, attacker, weapon, headshot = 0, 0, "?", false
    pcall(function() userid   = ev:GetInt("userid") or 0 end)
    pcall(function() attacker = ev:GetInt("attacker") or 0 end)
    pcall(function() weapon   = ev:GetString("weapon") or "?" end)
    pcall(function() headshot = ev:GetBool("headshot") == true end)

    local victim_idx   = userid_to_index(userid)
    local attacker_idx = userid_to_index(attacker)

    local victim_name   = player_name_by_index(victim_idx)
    local attacker_name = player_name_by_index(attacker_idx)

    local victim_ent   = entity_by_index(victim_idx)
    local attacker_ent = entity_by_index(attacker_idx)

    local msg = get_team_prefix(attacker_ent) .. attacker_name
        .. " killed "
        .. get_team_prefix(victim_ent) .. victim_name
        .. " with " .. tostring(weapon)
        .. (headshot and " (HEADSHOT)" or "")

    PrintChat(msg, 0)
end

local death_id
pcall(function() death_id = events.add_listener("player_death", on_death) end)

local function strip_and_zero(name)
    local cv = Cvars.FindVar(name)
    if not cv then return end
    pcall(function() cv:RemoveFlags(FCVAR_CHEAT) end)
    pcall(function() cv:RemoveFlags(FCVAR_PROTECTED) end)
    pcall(function() cv:SetInt(0) end)
end

local function apply_bypass()
    strip_and_zero("sv_consistency")
    strip_and_zero("sv_pure")
end

function on_create_move(cmd, local_player)
    apply_bypass()
end

function on_level_init_pre(mapname)
    apply_bypass()
end

function on_unload()
    pcall(function()
        if death_id then events.remove_listener("player_death", death_id) end
    end)
end

apply_bypass()
client.print("[KillNotify] loaded")



