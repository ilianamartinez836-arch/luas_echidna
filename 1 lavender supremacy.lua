-- ============================================================================
-- ☠ SUPREMACY + LAVENDER (DEFINITIVE HVH SUITE) — ECHIDNA (L4D2)
-- Architecture: Uncoupled Hooks + Continuous Permachoke + Single Owner
-- ============================================================================
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_supremacy_lavender_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
    short GetAsyncKeyState(int vKey);
]])

local PAGE_EXECUTE_READWRITE = 0x40

-- ============================================================================
-- CONFIGURACION
-- ============================================================================

-- Seccion 1: Supremacy (Turbo Desync / Inmortalidad)
local supremacy_cfg = {
    enabled        = true,
    turbo_val      = 135,
    key            = 0x43,       -- Tecla 'C' por defecto
    mode_toggle    = false,      -- false = HOLD (mantener) | true = TOGGLE
    hp_buffer_lock = true,
}

-- Seccion 2: Lavender (Choke Fluido de Combate)
local lavender_cfg = {
    enabled      = true,
    choke_value  = 3,            -- Choke base fluido
    key          = 0x56,         -- Tecla 'V' por defecto
    mode_toggle  = true,          -- Toggle ON / OFF
    show_ui      = true,
    ui_x         = 35,
    ui_y         = 520,
    ui_color     = { 0.765, 0.608, 1.000, 1.0 }, -- Lavanda puro
}

-- ============================================================================
-- OFFSETS VERIFICADOS (CL_Move.cpp / Doc 04 / Memory Probe)
-- ============================================================================
local ENGINE_CS_OFF    = 4352236  -- *(engine_base + 4352236) = raw client_state
local CS_NETCHAN_OFF   = 24       -- client_state + 24 = netchan
local CS_CHOKED_OFF    = 19024    -- client_state + 19024 = Choked_Commands
local NC_ACK_OFF       = 16       -- netchan + 16 = m_nOutSequenceNrAck
local NC_CHOKED_OFF    = 28       -- netchan + 28 = m_nChokedPackets

local NOP_PATTERN      = "85 C0 7E ?? 0F B6 C8"
local NOP_BYTES        = 4

-- ============================================================================
-- ESTADO INTERNO
-- ============================================================================
local engine_base         = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))
local patch_addr          = nil
local orig_bytes_str      = nil
local genuine_ack         = nil
local genuine_chok        = nil

-- Estados de activacion
local supremacy_active    = false
local supremacy_latch     = false
local lavender_active     = false
local lavender_latch      = false

local binding_target      = nil -- "supremacy" o "lavender"

-- Wrap detection
local last_curtime        = -1.0
local wrap_detected       = false

local function log(msg)
    pcall(function() client.print("[Supremacy-Lav] " .. tostring(msg)) end)
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

-- ============================================================================
-- 1. CAPA MOTOR: PARCHE NOP DE HEAVEN (DESBLOQUEO DE LIMITES)
-- ============================================================================
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

-- ============================================================================
-- RESOLUCION DE PUNTEROS
-- ============================================================================
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

-- ============================================================================
-- KEY SYSTEM UNIVERSAL (A-Z, 0-9, MOUSE1-5)
-- ============================================================================
local KEY_NAMES = {
    [0x01]="MOUSE1", [0x02]="MOUSE2", [0x04]="MOUSE3", [0x05]="MOUSE4", [0x06]="MOUSE5",
    [0x08]="BACKSPACE", [0x09]="TAB", [0x0D]="ENTER", [0x10]="SHIFT", [0x11]="CTRL", [0x12]="ALT",
    [0x14]="CAPS", [0x1B]="ESC", [0x20]="SPACE", [0x2D]="INSERT", [0x2E]="DELETE",
}
for i = 0x41, 0x5A do KEY_NAMES[i] = string.char(i) end
for i = 0x30, 0x39 do KEY_NAMES[i] = string.char(i) end

local function get_key_name(vk)
    if not vk or vk == 0 then return "NONE" end
    return KEY_NAMES[vk] or ("0x" .. string.format("%X", vk))
end

local function is_key_down(vk)
    if not vk or vk == 0 then return false end
    return bit.band(ffi.C.GetAsyncKeyState(vk), 0x8000) ~= 0
end

-- Captura de teclas en tiempo real
function on_key_down(key)
    if binding_target then
        if key == 0x1B then
            if binding_target == "supremacy" then supremacy_cfg.key = 0 end
            if binding_target == "lavender" then lavender_cfg.key = 0 end
            binding_target = nil
            return
        end

        if binding_target == "supremacy" then
            supremacy_cfg.key = key
            log("Tecla Supremacy asignada: " .. get_key_name(key))
        elseif binding_target == "lavender" then
            lavender_cfg.key = key
            log("Tecla Lavender asignada: " .. get_key_name(key))
        end
        binding_target = nil
    end
end

-- ============================================================================
-- GODMODE HP BUFFER LOCK (VIDA TEMPORAL PERMANENTE)
-- ============================================================================
local function apply_hp_buffer_lock(lp)
    if not supremacy_cfg.hp_buffer_lock or not lp or not lp:is_alive() then return end

    pcall(function()
        local buf = lp:get_prop_float("CTerrorPlayer", "m_healthBuffer") or 0.0
        if buf > 0.1 then
            local cur_time = GlobalVars.curtime() or 0.0
            lp:set_prop_float("CTerrorPlayer", "m_healthBufferTime", cur_time + 99999.0)
        end
    end)
end

-- ============================================================================
-- DETECCION DE WRAPS (BYXSTORM CL_MOVE)
-- ============================================================================
local function check_backlog_wrap(lp)
    if not lp then return false end
    local ok_tb, tb = pcall(lp.get_prop_int, lp, "CBasePlayer", "m_nTickBase")
    if not ok_tb or not tb then return false end
    local ipt = GlobalVars.interval_per_tick() or 0.0333
    local cur_time = tb * ipt

    if last_curtime > 0 and (last_curtime - cur_time) > 1.0 then
        wrap_detected = true
        last_curtime = cur_time
        return true
    end

    last_curtime = cur_time
    wrap_detected = false
    return false
end

-- ============================================================================
-- 2. CAPA PRE-FRAME: ON_CL_MOVE_PRE (LAVENDER + PERMACHOKE PASIVO)
-- ============================================================================
function on_cl_move_pre()
    if _G.echidna_supremacy_lavender_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    local cs = get_client_state()
    if not cs then return end

    local nc = get_netchannel(cs)
    if not nc then return end

    -- A) CAPTURA GENUINA SINGLE OWNER (Solo una vez)
    if not genuine_ack then
        local cur_ack = read_int(nc + NC_ACK_OFF)
        local cur_chk = read_int(nc + NC_CHOKED_OFF)
        if cur_ack and cur_ack ~= -1 then
            genuine_ack  = cur_ack
            genuine_chok = cur_chk or 0
        end
    end

    -- B) PERMACHOKE PASIVO: SIEMPRE ACTIVO EN SEGUNDO PLANO (-1 / 255)
    -- Esto blinda tu socket y crea el banco de reserva sin tocar ninguna tecla
    write_int_safe(nc + NC_ACK_OFF, -1)
    write_int_safe(nc + NC_CHOKED_OFF, 255)

    -- C) PROCESAR TECLA LAVENDER
    if lavender_cfg.key ~= 0 then
        local down = is_key_down(lavender_cfg.key)
        if lavender_cfg.mode_toggle then
            if down and not lavender_latch then
                lavender_active = not lavender_active
            end
            lavender_latch = down
        else
            lavender_active = down
        end
    end

    -- D) APLICAR LAVENDER EN EL PRE-FRAME (FLUIDEZ NATIVA TOTAL)
    -- Solo aplica si Supremacy Turbo NO esta activo (Supremacy tiene prioridad)
    if not supremacy_active then
        if lavender_cfg.enabled and lavender_active then
            write_int_safe(cs + CS_CHOKED_OFF, lavender_cfg.choke_value)
        else
            write_int_safe(cs + CS_CHOKED_OFF, 0)
        end
    end
end

-- ============================================================================
-- 3. CAPA CREATEMOVE: ON_CREATE_MOVE (SUPREMACY TURBO DESYNC)
-- ============================================================================
function on_create_move(cmd, lp)
    if _G.echidna_supremacy_lavender_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    -- Procesar tecla Supremacy
    if supremacy_cfg.key ~= 0 then
        local down = is_key_down(supremacy_cfg.key)
        if supremacy_cfg.mode_toggle then
            if down and not supremacy_latch then
                supremacy_active = not supremacy_active
            end
            supremacy_latch = down
        else
            supremacy_active = down
        end
    end

    if lp then
        apply_hp_buffer_lock(lp)
        check_backlog_wrap(lp)
    end

    local cs = get_client_state()
    if not cs then return end

    -- TURBO DESYNC SUPREMACY (135 CLAVADO EN MEMORIA)
    if supremacy_cfg.enabled and supremacy_active then
        write_int_safe(cs + CS_CHOKED_OFF, supremacy_cfg.turbo_val)
    end
end

-- ============================================================================
-- 4. UI Y WATERMARK EN PANTALLA (ON_END_SCENE)
-- ============================================================================
function on_end_scene()
    if _G.echidna_supremacy_lavender_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    -- Captura de raton si estamos bindeando
    if binding_target then
        for vk = 0x02, 0x06 do
            if vk ~= 0x01 and is_key_down(vk) then
                if binding_target == "supremacy" then supremacy_cfg.key = vk end
                if binding_target == "lavender" then lavender_cfg.key = vk end
                binding_target = nil
                break
            end
        end
    end

    -- Watermark Lavanda en pantalla
    if lavender_cfg.show_ui and lavender_cfg.enabled then
        local dl = imgui.get_foreground_draw_list()
        if dl then
            local x = lavender_cfg.ui_x
            local y = lavender_cfg.ui_y
            local col = lavender_cfg.ui_color

            local status_text = lavender_active and string.format("Lavender [ON: %d]", lavender_cfg.choke_value) or "Lavender [OFF]"
            if supremacy_active then
                status_text = string.format("Supremacy [TURBO: %d]", supremacy_cfg.turbo_val)
            end

            local tw = imgui.CalcTextSize(status_text)
            dl:add_rect_filled(x - 6, y - 3, x + tw + 6, y + 17, 0.05, 0.05, 0.08, 0.75, 4)
            dl:add_rect_filled(x - 6, y - 3, x - 3, y + 17, col[1], col[2], col[3], 1.0, 2)
            dl:add_text(x + 2, y, col[1], col[2], col[3], col[4], status_text)

            if wrap_detected then
                dl:add_text(x + 2, y + 18, 1.0, 0.3, 0.3, 1.0, "[WRAP DETECTED]")
            end
        end
    end
end

-- ============================================================================
-- 5. MENU DEDICADO EN ECHIDNA (PESTAÑA ☠ Supremacy + Lavender)
-- ============================================================================
pcall(function()
    menu.add_main_tab("Z", "Supremacy Suite", function()
        pcall(function()
            if imgui.Spacing then imgui.Spacing() end
            imgui.TextColored(0.4, 0.85, 1.0, 1.0, "☠ SUPREMACY + LAVENDER")
            imgui.SameLine()
            imgui.TextDisabled("// Definitive HvH Network Architecture")
            if imgui.Separator then imgui.Separator() end
            if imgui.Spacing then imgui.Spacing() end

            -- TARJETA 1: SUPREMACY (TURBO / GODMODE)
            imgui.BeginChild("##card_supremacy", 270, 290, true)
                imgui.TextColored(0.35, 0.85, 1.0, 1.0, "Supremacy (Turbo & Godmode)")
                imgui.Separator()
                imgui.Spacing()

                local v1 = imgui.Checkbox("Enable Supremacy##sup_en", supremacy_cfg.enabled)
                if v1 ~= nil then supremacy_cfg.enabled = v1 end

                local v2 = imgui.Checkbox("Godmode HP Buffer Lock##sup_hp", supremacy_cfg.hp_buffer_lock)
                if v2 ~= nil then supremacy_cfg.hp_buffer_lock = v2 end

                imgui.Spacing()
                local nv = imgui.SliderInt("Turbo Choke##sup_val", supremacy_cfg.turbo_val, 45, 145)
                if nv ~= nil then supremacy_cfg.turbo_val = nv end

                imgui.Spacing()
                local m_str = supremacy_cfg.mode_toggle and "Tipo: [ TOGGLE ]##sup_m" or "Tipo: [ HOLD ]##sup_m"
                if imgui.Button(m_str, 120, 22) then
                    supremacy_cfg.mode_toggle = not supremacy_cfg.mode_toggle
                    supremacy_active = false
                end

                imgui.SameLine()
                local k_str = (binding_target == "supremacy") and "[ Press Key... ]##sup_k" or string.format("Tecla: [ %s ]##sup_k", get_key_name(supremacy_cfg.key))
                if imgui.Button(k_str, 120, 22) then
                    binding_target = (binding_target == "supremacy") and nil or "supremacy"
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.TextDisabled("• Permachoke (-1/255) activo siempre.\n• Clava 135 para Desync Fantasma.")
            imgui.EndChild()

            imgui.SameLine()

            -- TARJETA 2: LAVENDER (CHOKE FLUIDO)
            imgui.BeginChild("##card_lavender", 270, 290, true)
                imgui.TextColored(0.765, 0.608, 1.0, 1.0, "Lavender (Fluid Combat Choke)")
                imgui.Separator()
                imgui.Spacing()

                local v3 = imgui.Checkbox("Enable Lavender##lav_en", lavender_cfg.enabled)
                if v3 ~= nil then lavender_cfg.enabled = v3 end

                local v4 = imgui.Checkbox("Show Watermark UI##lav_ui", lavender_cfg.show_ui)
                if v4 ~= nil then lavender_cfg.show_ui = v4 end

                imgui.Spacing()
                local l_val = imgui.SliderInt("Choke Value##lav_val", lavender_cfg.choke_value, 1, 20)
                if l_val ~= nil then lavender_cfg.choke_value = l_val end

                imgui.Spacing()
                local lm_str = lavender_cfg.mode_toggle and "Tipo: [ TOGGLE ]##lav_m" or "Tipo: [ HOLD ]##lav_m"
                if imgui.Button(lm_str, 120, 22) then
                    lavender_cfg.mode_toggle = not lavender_cfg.mode_toggle
                    lavender_active = false
                end

                imgui.SameLine()
                local lk_str = (binding_target == "lavender") and "[ Press Key... ]##lav_k" or string.format("Tecla: [ %s ]##lav_k", get_key_name(lavender_cfg.key))
                if imgui.Button(lk_str, 120, 22) then
                    binding_target = (binding_target == "lavender") and nil or "lavender"
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.TextDisabled("• Corre en on_cl_move_pre.\n• Movimiento 100% fluido sin tirones.")
            imgui.EndChild()
        end)
    end)
end)

-- ============================================================================
-- DESCARGA SEGURA
-- ============================================================================
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

    patch_addr       = nil
    orig_bytes_str   = nil
    genuine_ack      = nil
    genuine_chok     = nil
    supremacy_active = false
    lavender_active  = false
    binding_target   = nil

    log("Descargado — Red y motor 100% restaurados limpiamente.")
end

log("Cargado — Pestaña '☠ Supremacy Suite' lista en el menú.")
