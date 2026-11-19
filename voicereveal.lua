-- Voice Revealer — Echidna (L4D2)
-- Te avisa en el chat cuando alguien habla por microfono
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_voicereveal_instance = INSTANCE

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local SHOW_WHEN_STOPPED = true -- true = avisa tambien cuando dejan de hablar

-- =========================================================================
-- FFI Y DEFINICIONES
-- =========================================================================
pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    void* GetProcAddress(void* hModule, const char* lpProcName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
]])

local PAGE_EXECUTE_READWRITE = 0x40

local function log(msg)
    pcall(client.print, "[VoiceReveal] " .. tostring(msg))
end

-- 1. CHudChat para imprimir en el chat client-side
local client_base = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("client.dll"))
local chat_ptr    = ffi.cast("void***", client_base + 0x757920)
local c_hud_chat  = chat_ptr and chat_ptr[0] or nil

local function print_to_chat(msg)
    if not c_hud_chat or ffi.cast("uintptr_t", c_hud_chat) < 0x10000 then return end
    local vtbl = ffi.cast("void***", c_hud_chat)[0]
    if not vtbl or vtbl[23] == nil then return end

    local fn_print = ffi.cast("void(__cdecl*)(void*, int, int, const char*, ...)", vtbl[23])
    pcall(fn_print, c_hud_chat, 0, 0, " " .. msg)
end

-- 2. Obtener IBaseClientDLL (VClient016 en L4D2)
local ci_raw = ffi.C.GetProcAddress(ffi.cast("void*", client_base), "CreateInterface")
if not ci_raw then
    log("Error: CreateInterface no encontrado.")
    return
end

local ci = ffi.cast("void*(__cdecl*)(const char*, int*)", ci_raw)
local baseclient = ci("VClient016", nil)
if not baseclient or ffi.cast("uintptr_t", baseclient) < 0x10000 then
    log("Error: VClient016 no encontrado.")
    return
end

-- 3. Hook a VoiceStatus (Slot 32 verificado)
local VOICE_IDX = 32
local vtable    = ffi.cast("uintptr_t**", baseclient)[0]
local orig_fn   = vtable[VOICE_IDX]
local entry_ptr = ffi.cast("uintptr_t*", ffi.cast("uintptr_t", vtable) + VOICE_IDX * 4)

local function patch_vmt(addr, val)
    local old_prot = ffi.new("unsigned long[1]")
    local p = ffi.cast("void*", addr)
    if ffi.C.VirtualProtect(p, 4, PAGE_EXECUTE_READWRITE, old_prot) ~= 0 then
        addr[0] = ffi.cast("uintptr_t", val)
        ffi.C.VirtualProtect(p, 4, old_prot[0], old_prot)
        return true
    end
    return false
end

local talking_state = {}

-- Guardamos el callback anclado para evitar que LuaJIT lo libere
_G.echidna_voicestatus_cb = ffi.cast(
    "void(__fastcall*)(void*, void*, int, int, int)",
    function(thisptr, edx, entindex, iSsSlot, bTalking)
        -- 1. Siempre llamar a la funcion original primero
        if orig_fn and orig_fn ~= 0 then
            local orig = ffi.cast("void(__fastcall*)(void*, void*, int, int, int)", orig_fn)
            pcall(orig, thisptr, nil, entindex, iSsSlot, bTalking)
        end

        if _G.echidna_voicereveal_instance ~= INSTANCE then return end
        if not EngineClient.IsInGame() then return end

        local is_talking = (bTalking ~= 0)
        local was_talking = talking_state[entindex] or false
        if was_talking == is_talking then return end
        talking_state[entindex] = is_talking

        -- No procesar si no queremos ver cuando se callan
        if not is_talking and not SHOW_WHEN_STOPPED then return end

        -- Ignorarnos a nosotros mismos
        local local_idx = EngineClient.GetLocalPlayer()
        if entindex == local_idx or entindex <= 0 then return end

        -- Obtener nombre y equipo del jugador
        local name = nil
        local p_info = EngineClient.GetPlayerInfo(entindex)
        if p_info and p_info:name() ~= "" then
            name = p_info:name()
        end

        local team = 0
        local ent = ClientEntityList.GetClientEntity(entindex)
        if ent and ent:is_valid() then
            name = name or ent:get_class_name()
            local p = ent:as("CTerrorPlayer")
            if p then team = p:get_team() end
        end

        name = name or ("Player#" .. tostring(entindex))

        local team_label = "(Desconocido)"
        if team == 2 then
            team_label = "(Survivor)"
        elseif team == 3 then
            team_label = "(Infected)"
        elseif team == 1 then
            team_label = "(Spectator)"
        end

        if is_talking then
            print_to_chat(string.format("[VOZ] %s %s : hablando", team_label, name))
        else
            print_to_chat(string.format("[VOZ] %s %s : silencio", team_label, name))
        end
    end
)

-- Aplicar hook en la vtable
if patch_vmt(entry_ptr, _G.echidna_voicestatus_cb) then
    log("Hook aplicado en VoiceStatus (Slot 32).")
else
    log("Error al aplicar hook de vtable.")
    return
end

-- =========================================================================
-- DESCARGA SEGURA (RESTAURACION DE VTABLE OBLIGATORIA)
-- =========================================================================
function on_unload()
    if entry_ptr ~= nil and orig_fn ~= 0 then
        patch_vmt(entry_ptr, orig_fn)
        log("VTable restaurada con exito.")
    end
    _G.echidna_voicestatus_cb = nil
    talking_state = {}
    log("Descargado.")
end
