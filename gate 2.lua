-- =========================================================================
-- ☠ SUPREMACY + LAVENDER (REPARADO DE RAÍZ) — ECHIDNA (L4D2)
-- Movimiento 100% fluido en reposo | Choke real al activar | Permachoke vivo muerto
-- =========================================================================
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_master_suplav_repaired = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
    short GetAsyncKeyState(int vKey);
]])

local PAGE_EXECUTE_READWRITE = 0x40

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local KEY_TOGGLE     = 0x43  -- Tecla 'C' (Toggle ON / OFF)
local CHOKE_BURST    = 135   -- Choke masivo para Godmode Breaker al activar
local COLOR_LAVENDER = { 0.765, 0.608, 1.000, 1.0 }

local engine_base    = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))

-- Estados
local is_active      = false
local genuine_ack    = nil
local genuine_chok   = nil
local patch_addr     = nil
local orig_bytes_str = nil

local function log(msg)
    pcall(function() client.print("[SupLav-Fix] " .. tostring(msg)) end)
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

local function write_double_safe(addr, val)
    if not addr or addr < 0x10000 then return false end
    local old_protect = ffi.new("unsigned long[1]")
    if ffi.C.VirtualProtect(ffi.cast("void*", addr), 8, PAGE_EXECUTE_READWRITE, old_protect) ~= 0 then
        local ok = pcall(function() ffi.cast("double*", addr)[0] = val end)
        ffi.C.VirtualProtect(ffi.cast("void*", addr), 8, old_protect[0], old_protect)
        return ok
    end
    return false
end

-- =========================================================================
-- PARCHE NOP DE HEAVEN EN ENGINE.DLL
-- =========================================================================
local function apply_nop_patch()
    local ok, addr = pcall(memory.find_pattern, "engine.dll", "85 C0 7E ?? 0F B6 C8")
    if not ok or not addr or addr == 0 then return end
    patch_addr = addr
    local ok2, bytes = pcall(memory.read_bytes, addr, 4)
    if ok2 then orig_bytes_str = bytes end
    pcall(memory.patch, addr, string.char(0x90, 0x90, 0x90, 0x90))
    log(string.format("Parche NOP activo @ 0x%X", addr))
end
pcall(apply_nop_patch)

-- Resolución fresca y dinámica en cada tick (para no perder el NetChan al morir)
local function get_ptrs()
    if not engine_base or engine_base == 0 then return nil, nil end
    local cs = read_int(engine_base + 4352236)
    if not cs or cs < 0x10000 then return nil, nil end
    
    local nc = read_int(cs + 24)
    if not nc or nc < 0x10000 then
        local ok, info = pcall(EngineClient.GetNetChannelInfo)
        if ok and info and not info:IsNull() then
            local p = info:GetPtr()
            if p then nc = tonumber(ffi.cast("uintptr_t", p)) end
        end
    end
    if not nc or nc < 0x10000 then return nil, nil end
    return cs, nc
end

-- =========================================================================
-- LOGICA CENTRAL EN ON_CL_MOVE_PRE (INMUNE A LA MUERTE)
-- =========================================================================
function on_cl_move_pre()
    if _G.echidna_master_suplav_repaired ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    local cs, nc = get_ptrs()
    if not cs or not nc then return end

    -- 1. Capturar ACK y Choked real una sola vez
    if not genuine_ack then
        local cur_ack = read_int(nc + 16)
        local cur_chk = read_int(nc + 28)
        if cur_ack and cur_ack ~= -1 then
            genuine_ack  = cur_ack
            genuine_chok = cur_chk or 0
        end
    end

    -- 2. PERMACHOKE REAL DE FONDO (ACK = -1):
    -- Mantiene el socket en modo reserva para no perder paquetes al morir,
    -- pero SIN FORZAR 255 DE CHOKE EN REPOSO para que tu movimiento sea 100% suave.
    write_int_safe(nc + 16, -1)

    -- 3. AL ACTIVAR CON LA TECLA 'C' -> DESATAR EL CHOKE Y LOS GATES
    if is_active then
        -- GATE 1: ClearTime = 0.0
        write_double_safe(nc + 184, 0.0)

        -- GATE 2: Resample Time = 0.0 (offset 120 en puntero crudo)
        write_double_safe(cs + 120, 0.0)

        -- GATE 3 + CHOKE MASIVO: Clavar los 135 en memoria
        write_int_safe(cs + 19024, CHOKE_BURST)

        -- Spoof de ChokedPackets a 255 solo mientras el exploit está activo
        write_int_safe(nc + 28, 255)
    else
        -- REPOSO: Choke en 0 absoluto (movimiento y disparos normales sin tirones)
        write_int_safe(cs + 19024, 0)
        write_int_safe(nc + 28, 0)
    end
end

-- =========================================================================
-- GODMODE HEALTHBUFFER LOCK EN CREATEMOVE
-- =========================================================================
function on_create_move(cmd, lp)
    if _G.echidna_master_suplav_repaired ~= INSTANCE then return end
    if not EngineClient.IsInGame() or not lp then return end

    -- Congelar vida temporal si estamos vivos
    pcall(function()
        if lp:is_alive() then
            local buf = lp:get_prop_float("CTerrorPlayer", "m_healthBuffer") or 0.0
            if buf > 0.1 then
                local curtime = GlobalVars.curtime() or 0.0
                lp:set_prop_float("CTerrorPlayer", "m_healthBufferTime", curtime + 99999.0)
            end
        end
    end)
end

-- =========================================================================
-- TOGGLE CON LA TECLA 'C'
-- =========================================================================
function on_key_down(key)
    if key == KEY_TOGGLE then
        is_active = not is_active
        log(is_active and "CHOKE BURST ACTIVADO (135 Choke + 3 Gates)" or "CHOKE DESACTIVADO (Movimiento normal fluido)")
    end
end

-- =========================================================================
-- UI EN PANTALLA
-- =========================================================================
function on_end_scene()
    if _G.echidna_master_suplav_repaired ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    local dl = imgui.get_foreground_draw_list()
    if not dl then return end

    local x = 35
    local y = 520
    local status_text = is_active and string.format("Lavender [BURST: %d]", CHOKE_BURST) or "Lavender [OFF - FLUIDO]"

    local tw = imgui.CalcTextSize(status_text)
    dl:add_rect_filled(x - 6, y - 3, x + tw + 6, y + 17, 0.05, 0.05, 0.08, 0.75, 4)
    dl:add_rect_filled(x - 6, y - 3, x - 3, y + 17, COLOR_LAVENDER[1], COLOR_LAVENDER[2], COLOR_LAVENDER[3], 1.0, 2)
    dl:add_text(x + 2, y, COLOR_LAVENDER[1], COLOR_LAVENDER[2], COLOR_LAVENDER[3], COLOR_LAVENDER[4], status_text)
end

-- =========================================================================
-- DESCARGA SEGURA
-- =========================================================================
function on_unload()
    if patch_addr and orig_bytes_str then
        pcall(function() memory.patch(patch_addr, orig_bytes_str) end)
    end

    local cs, nc = get_ptrs()
    if cs then
        write_int_safe(cs + 19024, 0)
    end
    if nc and genuine_ack and genuine_ack ~= -1 then
        write_int_safe(nc + 16, genuine_ack)
        if genuine_chok and genuine_chok ~= 255 then
            write_int_safe(nc + 28, genuine_chok)
        end
    end

    patch_addr       = nil
    orig_bytes_str   = nil
    genuine_ack      = nil
    genuine_chok     = nil
    is_active        = false

    log("Descargado — Red y motor 100% restaurados.")
end

log("Cargado — En reposo movimiento 100% fluido. Presiona 'C' para el Burst 135.")
