-- Master Choke Definitivo (Hitbox Desync / Inmortalidad) — Echidna (L4D2)
-- Logica exacta del Master Choke original + Menu de configuracion
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_masterchoke_final_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
    short GetAsyncKeyState(int vKey);
]])

local PAGE_EXECUTE_READWRITE = 0x40

-- =========================================================================
-- CONFIGURACION (MODIFICABLE EN EL MENU)
-- =========================================================================
local cfg = {
    enabled   = true,
    key       = 0x43,   -- Tecla 'C' (Virtual-Key 0x43)
    turbo_val = 135,    -- Valor exacto de 135 que rompe la hitbox en el server
}

-- =========================================================================
-- OFFSETS VERIFICADOS
-- =========================================================================
local ENGINE_CS_OFF    = 4352236  -- *(engine_base + 4352236) = client_state crudo
local CS_NETCHAN_OFF   = 24       -- client_state + 24 = netchan
local CS_CHOKED_OFF    = 19024    -- client_state + 19024 = Choked_Commands
local NC_ACK_OFF       = 16       -- netchan + 16 = m_nOutSequenceNrAck
local NC_CHOKED_OFF    = 28       -- netchan + 28 = m_nChokedPackets

local NOP_PATTERN      = "85 C0 7E ?? 0F B6 C8"
local NOP_BYTES        = 4

-- =========================================================================
-- ESTADO
-- =========================================================================
local engine_base      = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))
local patch_addr       = nil
local orig_bytes_str   = nil
local genuine_ack      = nil
local genuine_chok     = nil
local was_holding_c    = false

local function log(msg)
    pcall(client.print, "[MasterChoke] " .. tostring(msg))
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
-- 1. PARCHE NOP DE HEAVEN (DESBLOQUEO DE MOTOR)
-- =========================================================================
local function apply_nop_patch()
    local addr = memory.find_pattern("engine.dll", NOP_PATTERN)
    if not addr or addr == 0 then return end

    patch_addr = addr
    orig_bytes_str = memory.read_bytes(addr, NOP_BYTES)

    local nops = string.char(0x90, 0x90, 0x90, 0x90)
    memory.patch(addr, nops)
    log(string.format("Parche NOP aplicado @ 0x%X", addr))
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

local function is_c_held()
    return bit.band(ffi.C.GetAsyncKeyState(cfg.key), 0x8000) ~= 0
end

-- =========================================================================
-- LOGICA EXACTA DEL MASTER CHOKE ORIGINAL
-- =========================================================================
function on_create_move(cmd, lp)
    if _G.echidna_masterchoke_final_instance ~= INSTANCE then return end
    if not cfg.enabled or not EngineClient.IsInGame() then return end

    local cs = get_client_state()
    if not cs then return end

    local nc = get_netchannel(cs)
    if not nc then return end

    -- Captura del estado genuino para restauracion limpia
    if not genuine_ack then
        local cur_ack = read_int(nc + NC_ACK_OFF)
        local cur_chk = read_int(nc + NC_CHOKED_OFF)
        if cur_ack and cur_ack ~= -1 then
            genuine_ack  = cur_ack
            genuine_chok = cur_chk or 0
        end
    end

    -- 1. SEGUNDO PLANO (PERMANENTE): Permachoke pasivo (-1 / 255)
    write_int_safe(nc + NC_ACK_OFF, -1)
    write_int_safe(nc + NC_CHOKED_OFF, 255)

    -- 2. TURBO: Solo al presionar la tecla 'C' se clavan los 135
    local holding_c = is_c_held()

    if holding_c then
        write_int_safe(cs + CS_CHOKED_OFF, cfg.turbo_val)
        was_holding_c = true
    else
        -- Al soltar la tecla, vuelve a 0 de inmediato (movimiento 100% fluido)
        if was_holding_c then
            write_int_safe(cs + CS_CHOKED_OFF, 0)
            was_holding_c = false
        end
    end
end

-- =========================================================================
-- MENU DEDICADO EN ECHIDNA
-- =========================================================================
pcall(function()
    menu.add_main_tab("M", "Master Choke", function()
        pcall(imgui.Spacing)
        pcall(imgui.TextColored, 0.7, 0.85, 1.0, 1.0, "Master Choke (Hitbox Desync / Inmortal)")
        pcall(imgui.Separator)
        pcall(imgui.Spacing)

        local cb, val = pcall(imgui.Checkbox, "Enable Master Choke##mcf_en", cfg.enabled)
        if cb and val ~= nil then cfg.enabled = val end

        pcall(imgui.Spacing)
        local sl, nv = pcall(imgui.SliderInt, "Turbo Choke Value (Hold C)##mcf_tur", cfg.turbo_val, 45, 180)
        if sl and nv ~= nil then cfg.turbo_val = nv end

        pcall(imgui.Spacing)
        pcall(imgui.Separator)
        pcall(imgui.TextColored, 0.3, 1.0, 0.3, 1.0, "Background:")
        pcall(imgui.Text, "• Permachoke pasivo (-1 / 255) activo")
        pcall(imgui.Text, "• NOP engine patch activo")
        pcall(imgui.Spacing)
        pcall(imgui.TextColored, 1.0, 0.8, 0.2, 1.0, "Al presionar 'C':")
        pcall(imgui.Text, string.format("• Inyecta %d de Choke (Hitbox Desync)", cfg.turbo_val))
        pcall(imgui.TextDisabled("• Al soltar la C vuelves a moverte normal"))
    end)
end)

-- =========================================================================
-- DESCARGA SEGURA
-- =========================================================================
function on_unload()
    -- Restaurar bytes del motor
    if patch_addr and orig_bytes_str then
        pcall(memory.patch, patch_addr, orig_bytes_str)
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
    was_holding_c = false
    log("Descargado y red restaurada limpiamente.")
end

log("Cargado con exito — Pasivo fluido activo. Manten 'C' para el Turbo 135.")
