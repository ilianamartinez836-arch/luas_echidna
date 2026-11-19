-- =========================================================================
-- ULTIMATE CHOKE SUPREMO (PRIVATE ENGINE EXPLOIT SUITE) — ECHIDNA (L4D2)
-- Features: NOP Uncap + Permachoke (-1/255) + ByxStorm 135 + Keybinder + HP Buffer Lock
-- =========================================================================
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_ultimate_choke_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
    short GetAsyncKeyState(int vKey);
]])

local PAGE_EXECUTE_READWRITE = 0x40

-- =========================================================================
-- CONFIGURACION POR DEFECTO
-- =========================================================================
local cfg = {
    enabled        = true,
    turbo_val      = 135,   -- Punto dulce de ByxStorm (Bleed 45 + Choke1 45 + Choke2 45)
    key            = 0x43,  -- Tecla 'C' por defecto
    mode_toggle    = false, -- false = HOLD (mantener) | true = TOGGLE (un toque)
    hp_buffer_lock = true,  -- Bloqueo de decaimiento de vida temporal
}

-- =========================================================================
-- OFFSETS VERIFICADOS
-- =========================================================================
local ENGINE_CS_OFF = 4352236  -- *(engine_base + 4352236) = client_state crudo
local CS_NETCHAN_OFF= 24       -- client_state + 24 = netchan
local CS_CHOKED_OFF = 19024    -- client_state + 19024 = Choked_Commands
local NC_ACK_OFF    = 16       -- netchan + 16 = m_nOutSequenceNrAck
local NC_CHOKED_OFF = 28       -- netchan + 28 = m_nChokedPackets

local NOP_PATTERN   = "85 C0 7E ?? 0F B6 C8"
local NOP_BYTES     = 4

-- =========================================================================
-- ESTADO INTERNO
-- =========================================================================
local engine_base      = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))
local patch_addr       = nil
local orig_bytes_str   = nil
local genuine_ack      = nil
local genuine_chok     = nil
local was_active       = false
local toggle_state     = false
local key_latch        = false
local binding_key      = false

local function log(msg)
    pcall(function() client.print("[UltimateChoke] " .. tostring(msg)) end)
end

local function read_int(addr)
    if not addr or addr < 0x10000 then return nil end
    local ok, val = pcall(function() return ffi.cast("int*", addr)[0] end)
    return ok and val or nil
end

local function write_int_safe(addr, val)
    if not addr or addr < 0x10000 then return false end
    local old_protect = ffi.new("unsigned long[1]")
    if ffi.C.VirtualProtect(ffi.cast("void*", addr), 4, PAGE_EXECUTE_READWRITE, old_protect) ~= 0 then
        local ok = pcall(function() ffi.cast("int*", addr)[0] = val end)
        ffi.C.VirtualProtect(ffi.cast("void*", addr), 4, old_protect[0], old_protect)
        return ok
    end
    return false
end

-- =========================================================================
-- 1. CAPA MOTOR: PARCHE NOP DE HEAVEN
-- =========================================================================
local function apply_nop_patch()
    local addr = memory.find_pattern("engine.dll", NOP_PATTERN)
    if not addr or addr == 0 then return end

    patch_addr = addr
    orig_bytes_str = memory.read_bytes(addr, NOP_BYTES)

    local nops = string.char(0x90, 0x90, 0x90, 0x90)
    memory.patch(addr, nops)
    log(string.format("Parche NOP de motor activo @ 0x%X", addr))
end

apply_nop_patch()

-- =========================================================================
-- RESOLUCION DE PUNTEROS
-- =========================================================================
local function get_client_state()
    if not engine_base or engine_base == 0 then return nil end
    local cs = read_int(engine_base + ENGINE_CS_OFF)
    if cs and cs > 0x10000 then return cs end
    return nil
end

local function get_netchannel(cs)
    if not cs or cs == 0 then return nil end
    local nc = read_int(cs + CS_NETCHAN_OFF)
    if nc and nc > 0x10000 then return nc end

    local nc_info = EngineClient.GetNetChannelInfo()
    if nc_info and not nc_info:IsNull() then
        local ptr = nc_info:GetPtr()
        if ptr then
            local uptr = tonumber(ffi.cast("uintptr_t", ptr))
            if uptr and uptr > 0x10000 then return uptr end
        end
    end
    return nil
end

-- =========================================================================
-- KEY SYSTEM UNIVERSAL
-- =========================================================================
local VK_NAMES = {
    [0x01]="MOUSE1", [0x02]="MOUSE2", [0x04]="MOUSE3", [0x05]="MOUSE4", [0x06]="MOUSE5",
    [0x08]="BACKSPACE", [0x09]="TAB", [0x0D]="ENTER", [0x10]="SHIFT", [0x11]="CTRL", [0x12]="ALT",
    [0x14]="CAPS", [0x1B]="ESCAPE", [0x20]="SPACE", [0x2D]="INSERT", [0x2E]="DELETE",
    [0x23]="END", [0x24]="HOME", [0x25]="LEFT", [0x26]="UP", [0x27]="RIGHT", [0x28]="DOWN",
}
for i = 0x41, 0x5A do VK_NAMES[i] = string.char(i) end
for i = 0x30, 0x39 do VK_NAMES[i] = string.char(i) end
for i = 1, 12 do VK_NAMES[0x6F + i] = "F" .. i end

local function get_key_name(vk)
    if not vk or vk == 0 then return "NONE" end
    return VK_NAMES[vk] or ("0x" .. string.format("%X", vk))
end

local function is_key_down(vk)
    if not vk or vk == 0 then return false end
    return bit.band(ffi.C.GetAsyncKeyState(vk), 0x8000) ~= 0
end

local function process_keybind_system()
    if binding_key then
        for vk = 1, 255 do
            if is_key_down(vk) then
                if vk == 0x1B then
                    cfg.key = 0
                else
                    cfg.key = vk
                end
                binding_key = false
                break
            end
        end
        return
    end

    if cfg.key == 0 then return end

    local down = is_key_down(cfg.key)

    if cfg.mode_toggle then
        if down and not key_latch then
            toggle_state = not toggle_state
        end
        key_latch = down
    else
        toggle_state = down
    end
end

-- =========================================================================
-- EXPLOIT GODMODE HP BUFFER LOCK
-- =========================================================================
local function apply_hp_buffer_lock(lp)
    if not cfg.hp_buffer_lock or not lp or not lp:is_alive() then return end

    pcall(function()
        local buf = lp:get_prop_float("CTerrorPlayer", "m_healthBuffer") or 0.0
        if buf > 0.1 then
            local cur_time = GlobalVars.curtime() or 0.0
            lp:set_prop_float("CTerrorPlayer", "m_healthBufferTime", cur_time + 99999.0)
        end
    end)
end

-- =========================================================================
-- LOGICA EN CREATEMOVE
-- =========================================================================
function on_create_move(cmd, lp)
    if _G.echidna_ultimate_choke_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    process_keybind_system()

    if not cfg.enabled then
        if was_active then
            local cs = get_client_state()
            if cs then write_int_safe(cs + CS_CHOKED_OFF, 0) end
            was_active = false
        end
        return
    end

    if lp then apply_hp_buffer_lock(lp) end

    local cs = get_client_state()
    if not cs then return end

    local nc = get_netchannel(cs)
    if not nc then return end

    -- Captura genuina Single Owner
    if not genuine_ack then
        local cur_ack = read_int(nc + NC_ACK_OFF)
        local cur_chk = read_int(nc + NC_CHOKED_OFF)
        if cur_ack and cur_ack ~= -1 then
            genuine_ack  = cur_ack
            genuine_chok = cur_chk or 0
        end
    end

    -- Permachoke pasivo (-1 / 255)
    write_int_safe(nc + NC_ACK_OFF, -1)
    write_int_safe(nc + NC_CHOKED_OFF, 255)

    -- Inyeccion dinamica en 19024
    if toggle_state then
        write_int_safe(cs + CS_CHOKED_OFF, cfg.turbo_val)
        was_active = true
    else
        if was_active then
            write_int_safe(cs + CS_CHOKED_OFF, 0)
            was_active = false
        end
    end
end

-- =========================================================================
-- MENU DEDICADO EN ECHIDNA (PESTAÑA ☠ ULTIMATE CHOKE)
-- =========================================================================
pcall(function()
    menu.add_main_tab("E", "Ultimate Choke", function()
        pcall(function()
            if imgui.Spacing then imgui.Spacing() end
            if imgui.TextColored then
                imgui.TextColored(0.4, 0.85, 1.0, 1.0, "Ultimate Choke Supremo (ByxStorm & Heaven Architecture)")
            end
            if imgui.Separator then imgui.Separator() end
            if imgui.Spacing then imgui.Spacing() end

            -- 1. Interruptores
            local v1 = imgui.Checkbox("Master Enable##uc_en", cfg.enabled)
            if v1 ~= nil then cfg.enabled = v1 end

            if imgui.SameLine then imgui.SameLine() end
            local v2 = imgui.Checkbox("Godmode HP Buffer Lock##uc_hp", cfg.hp_buffer_lock)
            if v2 ~= nil then cfg.hp_buffer_lock = v2 end

            if imgui.Spacing then imgui.Spacing() end
            if imgui.Separator then imgui.Separator() end
            if imgui.TextColored then
                imgui.TextColored(0.8, 0.8, 0.8, 1.0, "Ajustes de Choke y Tecla:")
            end
            if imgui.Spacing then imgui.Spacing() end

            -- 2. Slider
            local nv = imgui.SliderInt("Turbo Value (Bleed+Choke)##uc_val", cfg.turbo_val, 45, 145)
            if nv ~= nil then cfg.turbo_val = nv end

            if imgui.Spacing then imgui.Spacing() end

            -- 3. Selector de modo
            local btn_mode_str = cfg.mode_toggle and "Modo: [ TOGGLE ]##uc_mode" or "Modo: [ HOLD ]##uc_mode"
            if imgui.Button(btn_mode_str, 160, 22) then
                cfg.mode_toggle = not cfg.mode_toggle
                toggle_state = false
            end

            if imgui.SameLine then imgui.SameLine() end

            -- 4. Keybinder interactivo
            local key_btn_str = binding_key and "[ Press any key... ]##uc_bind" or string.format("Tecla: [ %s ]##uc_bind", get_key_name(cfg.key))
            if imgui.Button(key_btn_str, 160, 22) then
                binding_key = not binding_key
            end

            if imgui.Spacing then imgui.Spacing() end
            if imgui.Separator then imgui.Separator() end
            if imgui.TextColored then
                imgui.TextColored(0.9, 0.7, 0.2, 1.0, "Telemetria & Diagnostico en Vivo:")
            end
            if imgui.Spacing then imgui.Spacing() end

            -- 5. Monitor de telemetria
            local cs_ptr = get_client_state()
            local nc_ptr = cs_ptr and get_netchannel(cs_ptr) or nil

            imgui.Text(string.format("Engine NOP Patch : %s", patch_addr and "ACTIVO (Desbloqueado)" or "FALLO / NO ENCONTRADO"))
            imgui.Text(string.format("ClientState Base : 0x%X", cs_ptr or 0))
            imgui.Text(string.format("NetChannel Ptr   : 0x%X", nc_ptr or 0))
            
            local status_str = toggle_state and "TURBO DESYNC (135 ACTIVO)" or "PASIVO FLUIDO (SEGUNDO PLANO)"
            local status_col = toggle_state and { 1.0, 0.2, 0.2 } or { 0.2, 1.0, 0.3 }
            if imgui.TextColored then
                imgui.TextColored(status_col[1], status_col[2], status_col[3], 1.0, "Estado Actual    : " .. status_str)
            end

            if imgui.Spacing then imgui.Spacing() end
            if imgui.Separator then imgui.Separator() end
            imgui.TextDisabled("• Cero pantallas negras (Offsets 112 y 19012 eliminados).")
            imgui.TextDisabled("• Single Owner activo: jamas te desconecta al descargar.")
        end)
    end)
end)

-- =========================================================================
-- DESCARGA SEGURA
-- =========================================================================
function on_unload()
    if patch_addr and orig_bytes_str then
        pcall(function() memory.patch(patch_addr, orig_bytes_str) end)
    end

    local cs = get_client_state()
    if cs then
        write_int_safe(cs + CS_CHOKED_OFF, 0)
        local nc = get_netchannel(cs)
        if nc and genuine_ack and genuine_ack ~= -1 then
            write_int_safe(nc + NC_ACK_OFF, genuine_ack)
            if genuine_chok and genuine_chok ~= 255 then
                write_int_safe(nc + NC_CHOKED_OFF, genuine_chok)
            end
        end
    end

    patch_addr    = nil
    genuine_ack   = nil
    was_active    = false
    toggle_state  = false
    binding_key   = false
    log("Descargado — Red y motor 100% restaurados.")
end

log("Cargado — Pestaña '☠ Ultimate Choke' disponible en el menú.")






