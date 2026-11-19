-- Permachoke Definitivo (ByxStorm Engine Port) — Echidna (L4D2)
-- Control total de red con los 3 gates, doble precision y menu dedicado
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_permachoke_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    short GetAsyncKeyState(int vKey);
]])

-- =========================================================================
-- CONFIGURACION Y ESTADO
-- =========================================================================
local TOGGLE_KEY = 0x43  -- Tecla 'C'

local CFG = {
    enabled     = false,
    base_value  = 45,    -- Valor base de choke
    max_value   = 200,   -- Techo duro de choke
    auto_adjust = true,  -- Ajuste dinamico segun latencia
    use_gate2   = true,  -- Forzar client_state + 112 (double) a 0.0
}

local st = {
    key_held     = false,
    has_genuine  = false,
    genuine_ack  = 0,
    genuine_chok = 0,
    current_val  = 45,
}

local function log(msg)
    pcall(client.print, "[Permachoke] " .. tostring(msg))
end

-- =========================================================================
-- HELPERS DE MEMORIA Y OFFSETS
-- =========================================================================
local ENGINE_CS_OFF    = 4352236  -- *(engine_base + 4352236) = client_state crudo
local CS_NETCHAN_OFF   = 24       -- client_state + 24 = netchan
local CS_CHOKED_OFF    = 19024    -- client_state + 19024 = choked_commands
local CS_RESAMPLE_OFF  = 112      -- client_state + 112 = proximo tiempo de muestreo (double)
local NC_ACK_OFF       = 16       -- netchan + 16 = m_nOutSequenceNrAck
local NC_CHOKED_OFF    = 28       -- netchan + 28 = m_nChokedPackets
local NC_CLEARTIME_OFF = 0xB8     -- netchan + 0xB8 = m_fClearTime

local function get_engine_base()
    local ok, b = pcall(memory.get_module_base, "engine.dll")
    if ok and b and b ~= 0 then return b end
    return 0
end

local function get_cs()
    local eng = get_engine_base()
    if eng == 0 then return 0 end
    local ok, cs = pcall(memory.read_i32, eng + ENGINE_CS_OFF)
    if not ok or not cs or cs == 0 then return 0 end
    return cs
end

local function get_nc(cs)
    if not cs or cs == 0 then return 0 end
    local ok, nc = pcall(memory.read_i32, cs + CS_NETCHAN_OFF)
    if ok and nc and nc ~= 0 then return nc end
    
    local nc_info = EngineClient.GetNetChannelInfo()
    if nc_info and not nc_info:IsNull() then
        local ptr = nc_info:GetPtr()
        if ptr then
            local uptr = tonumber(ffi.cast("uintptr_t", ptr))
            if uptr and uptr > 0x10000 then return uptr end
        end
    end
    return 0
end

-- Escritura segura de un valor Double (64 bits) para el Gate 2
local function write_double(addr, val)
    pcall(function()
        ffi.cast("double*", addr)[0] = val
    end)
end

-- =========================================================================
-- CAPTURA Y SPOOF DE NETCHANNEL (SINGLE OWNER)
-- =========================================================================
local function capture_genuine(nc)
    if st.has_genuine then return end
    if not nc or nc == 0 then return end
    local ok1, ack = pcall(memory.read_i32, nc + NC_ACK_OFF)
    local ok2, chk = pcall(memory.read_i32, nc + NC_CHOKED_OFF)
    if ok1 and ack and ack ~= -1 then
        st.genuine_ack  = ack
        st.genuine_chok = ok2 and chk or 0
        st.has_genuine  = true
    end
end

local function spoof_nc(nc)
    if not nc or nc == 0 then return end
    pcall(memory.write_i32, nc + NC_ACK_OFF, -1)
    pcall(memory.write_i32, nc + NC_CHOKED_OFF, 255)
end

local function restore_nc(nc)
    if not nc or nc == 0 or not st.has_genuine then return end
    local ok, cur_ack = pcall(memory.read_i32, nc + NC_ACK_OFF)
    if ok and cur_ack == -1 then
        pcall(memory.write_i32, nc + NC_ACK_OFF, st.genuine_ack)
    end
    local ok2, cur_chk = pcall(memory.read_i32, nc + NC_CHOKED_OFF)
    if ok2 and cur_chk == 255 then
        pcall(memory.write_i32, nc + NC_CHOKED_OFF, st.genuine_chok)
    end
    st.has_genuine = false
end

-- =========================================================================
-- CALCULO DINAMICO POR PING
-- =========================================================================
local function get_target_value()
    if not CFG.auto_adjust then return CFG.base_value end

    local nc_info = EngineClient.GetNetChannelInfo()
    if not nc_info or nc_info:IsNull() then return CFG.base_value end

    local ping = (nc_info:GetAvgLatency(1) or 0) * 1000 -- ms
    local v = CFG.base_value + math.floor(ping / 10)

    if v > CFG.max_value then v = CFG.max_value end
    if v < CFG.base_value then v = CFG.base_value end

    st.current_val = v
    return v
end

-- =========================================================================
-- TOGGLE CON TECLA 'C'
-- =========================================================================
local function is_key_down(vk)
    return bit.band(ffi.C.GetAsyncKeyState(vk), 0x8000) ~= 0
end

local function handle_toggle()
    local down = is_key_down(TOGGLE_KEY)
    if down and not st.key_held then
        st.key_held = true
        CFG.enabled = not CFG.enabled
        log(CFG.enabled and "ACTIVADO" or "DESACTIVADO")

        if not CFG.enabled then
            local nc = get_nc(get_cs())
            restore_nc(nc)
        end
    elseif not down then
        st.key_held = false
    end
end

-- =========================================================================
-- LOGICA EN ON_CL_MOVE_PRE
-- =========================================================================
function on_cl_move_pre()
    if _G.echidna_permachoke_instance ~= INSTANCE then return end

    handle_toggle()

    if not CFG.enabled or not EngineClient.IsInGame() then
        local cs = get_cs()
        local nc = get_nc(cs)
        if nc ~= 0 and st.has_genuine then
            restore_nc(nc)
        end
        return
    end

    local cs = get_cs()
    if cs == 0 then return end
    local nc = get_nc(cs)
    if nc == 0 then return end

    capture_genuine(nc)

    local target_choke = get_target_value()

    -- Gate 1: m_fClearTime al futuro
    pcall(memory.write_f32, nc + NC_CLEARTIME_OFF, 999999.0)

    -- Gate 2: client_state + 112 escrito como double (0.0)
    if CFG.use_gate2 then
        write_double(cs + CS_RESAMPLE_OFF, 0.0)
    end

    -- Escritura principal del Choke
    pcall(memory.write_i32, cs + CS_CHOKED_OFF, target_choke)

    -- Spoof final de NetChannel
    spoof_nc(nc)
end

-- =========================================================================
-- MENU DE CONFIGURACION NUEVO EN ECHIDNA
-- =========================================================================
local menu_ok = false
pcall(function()
    menu.add_main_tab("P", "Permachoke", function()
        pcall(imgui.Spacing)
        pcall(imgui.TextColored, 0.7, 0.85, 1.0, 1.0, "Permachoke (ByxStorm Engine)")
        pcall(imgui.Separator)
        pcall(imgui.Spacing)

        local cb, val = pcall(imgui.Checkbox, "Enabled##pch_en", CFG.enabled)
        if cb and val ~= nil and val ~= CFG.enabled then
            CFG.enabled = val
            if not val then
                local nc = get_nc(get_cs())
                restore_nc(nc)
            end
        end

        pcall(imgui.Spacing)
        local sl1, nv1 = pcall(imgui.SliderInt, "Base Value##pch_base", CFG.base_value, 1, 200)
        if sl1 and nv1 ~= nil then CFG.base_value = nv1 end

        local sl2, nv2 = pcall(imgui.SliderInt, "Max Value##pch_max", CFG.max_value, 50, 500)
        if sl2 and nv2 ~= nil then CFG.max_value = nv2 end

        pcall(imgui.Spacing)
        pcall(imgui.Separator)

        local cb2, val2 = pcall(imgui.Checkbox, "Auto-Adjust by Ping##pch_auto", CFG.auto_adjust)
        if cb2 and val2 ~= nil then CFG.auto_adjust = val2 end

        local cb3, val3 = pcall(imgui.Checkbox, "Gate 2 (Resample Double)##pch_g2", CFG.use_gate2)
        if cb3 and val3 ~= nil then CFG.use_gate2 = val3 end

        pcall(imgui.Spacing)
        pcall(imgui.Separator)
        pcall(imgui.Text, string.format("Current Choke Value: %d", st.current_val))
        pcall(imgui.Text, string.format("Status: %s", CFG.enabled and "ACTIVE (Key: C)" or "OFF"))
    end)
    menu_ok = true
end)

-- =========================================================================
-- DESCARGA SEGURA
-- =========================================================================
function on_unload()
    CFG.enabled = false
    local cs = get_cs()
    local nc = get_nc(cs)
    if nc ~= 0 then
        restore_nc(nc)
        pcall(memory.write_f32, nc + NC_CLEARTIME_OFF, 0.0)
    end
    if cs ~= 0 then
        pcall(memory.write_i32, cs + CS_CHOKED_OFF, 0)
    end
    log("Descargado y red restaurada.")
end

log("Cargado — Presiona 'C' para alternar o abre la pestaña 'Permachoke' en el menú.")
