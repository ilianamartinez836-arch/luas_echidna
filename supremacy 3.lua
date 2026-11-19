-- ============================================================================
-- LAVENDER - Ultimate HvH Network Controller for Echidna L4D2
-- ============================================================================
-- Arquitectura:
-- 1. Permachoke SIEMPRE activo (netchan +16/-1, +28/255) - estilo Supremacy
-- 2. Choke base SIEMPRE activo (client_state + 19024 = 3) - lag constante
-- 3. Gate 1 SIEMPRE activo (netchan + 184 = 0.0) - envío forzado
-- 4. Toggle C: cambia choke base de 3 a 20 (burst mode)
-- 5. SIN Gate 2 (confirmado que causa crash/kick)
-- ============================================================================

local ffi = require("ffi")

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
]])

local PAGE_EXECUTE_READWRITE = 0x40
local VK_C = 0x43

-- Configuración
local CFG = {
    choke_base = 3,      -- Valor base SIEMPRE activo (lag constante)
    choke_burst = 20,    -- Valor al presionar C (burst mode)
    ui_x = 150,
    ui_y = 20,
    ui_color = {180/255, 130/255, 255/255, 1.0},  -- Lavanda púrpura
}

-- Instancia única para evitar conflictos con otros scripts
local INSTANCE = {}
_G.echidna_lavender_instance = INSTANCE

-- Base del motor para acceder a offsets crudos
local engine_base = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))

-- Estado genuino de la red (Single Owner Pattern)
-- Capturado UNA SOLA VEZ antes de cualquier manipulación
local genuine_ack = nil
local genuine_choked = nil

-- Detección de backlog wrap
local last_curtime = -1.0
local wrap_detected = false

-- Toggle del choke burst
local choke_burst_enabled = false
local key_held = false

-- ============================================================================
-- FUNCIONES DE MEMORIA SEGURAS
-- ============================================================================

local function read_int(addr)
    if not addr or addr < 0x10000 then return nil end
    local ok, val = pcall(function() return ffi.cast("int*", addr)[0] end)
    return ok and val or nil
end

local function read_double(addr)
    if not addr or addr < 0x10000 then return nil end
    local ok, val = pcall(function() return ffi.cast("double*", addr)[0] end)
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

-- ============================================================================
-- OBTENER PUNTEROS DE RED
-- ============================================================================

local function get_netchan_and_client_state()
    if not engine_base or engine_base == 0 then return nil, nil end

    -- client_state crudo: engine.dll + 4352236
    local client_state_ptr = read_int(engine_base + 4352236)
    if not client_state_ptr or client_state_ptr == 0 then return nil, nil end

    -- netchan: client_state + 24
    local netchan = read_int(client_state_ptr + 24)
    if not netchan or netchan == 0 then 
        -- Fallback: API de Echidna
        local ok, nc_info = pcall(EngineClient.GetNetChannelInfo)
        if ok and nc_info and not nc_info:IsNull() then
            local ptr = nc_info:GetPtr()
            if ptr then netchan = tonumber(ffi.cast("uintptr_t", ptr)) end
        end
    end
    if not netchan or netchan == 0 then return nil, nil end

    return netchan, client_state_ptr
end

-- ============================================================================
-- CAPTURA DEL ESTADO GENUINO (Single Owner)
-- ============================================================================

local function capture_genuine_state(netchan)
    -- Solo capturar si aún no tenemos el snapshot genuino
    if genuine_ack == nil then
        local cur_ack = read_int(netchan + 16)   -- m_nOutSequenceNrAck
        local cur_choked = read_int(netchan + 28) -- m_nChokedPackets
        -- Solo capturar si el valor NO es el que nosotros forzamos (-1)
        if cur_ack and cur_ack ~= -1 then
            genuine_ack = cur_ack
            genuine_choked = cur_choked or 0
        end
    end
end

-- ============================================================================
-- APLICAR PERMACHOKE + CHOKE BASE + GATE 1 (SIEMPRE ACTIVO)
-- ============================================================================

local function apply_base_exploit()
    local netchan, client_state_ptr = get_netchan_and_client_state()
    if not netchan or not client_state_ptr then return false end

    -- Capturar estado genuino ANTES de manipular
    capture_genuine_state(netchan)

    -- Gate 1: Forzar CanPacket() a true (m_fClearTime = 0.0)
    write_double_safe(netchan + 184, 0.0)

    -- Choke base SIEMPRE activo (valor 3)
    -- Esto hace que cada paquete lleve 3 comandos de respaldo agrupados
    -- Resultado: lag constante y procesamiento masivo de daño
    write_int_safe(client_state_ptr + 19024, CFG.choke_base)

    -- Permachoke: Spoof defensivo para evitar desconexión
    write_int_safe(netchan + 16, -1)   -- m_nOutSequenceNrAck
    write_int_safe(netchan + 28, 255)  -- m_nChokedPackets

    return true
end

-- ============================================================================
-- APLICAR CHOKE BURST (SOLO AL PRESIONAR C)
-- ============================================================================

local function apply_choke_burst()
    local netchan, client_state_ptr = get_netchan_and_client_state()
    if not netchan or not client_state_ptr then return false end

    -- Capturar estado genuino ANTES de manipular
    capture_genuine_state(netchan)

    -- Gate 1: Forzar CanPacket() a true (m_fClearTime = 0.0)
    write_double_safe(netchan + 184, 0.0)

    -- Choke burst (valor 20) - multiplica el lag base
    write_int_safe(client_state_ptr + 19024, CFG.choke_burst)

    -- Permachoke: Spoof defensivo
    write_int_safe(netchan + 16, -1)
    write_int_safe(netchan + 28, 255)

    return true
end

-- ============================================================================
-- RESTAURACIÓN CONDICIONAL (C4: Solo si el valor sigue siendo el que forzamos)
-- ============================================================================

local function restore_network_state()
    local netchan, client_state_ptr = get_netchan_and_client_state()
    if not netchan then return end

    -- Leer valores actuales
    local cur_ack = read_int(netchan + 16)
    local cur_choked = read_int(netchan + 28)

    -- Solo restaurar si el valor SIGUE siendo el que forzamos
    -- Esto evita sobreescribir ACKs genuinos que llegaron durante el proceso
    if cur_ack == -1 and genuine_ack ~= nil then
        write_int_safe(netchan + 16, genuine_ack)
    end
    if cur_choked == 255 and genuine_choked ~= nil then
        write_int_safe(netchan + 28, genuine_choked)
    end

    -- Resetear choke a 0 solo al descargar completamente
    if client_state_ptr then
        write_int_safe(client_state_ptr + 19024, 0)
    end
end

-- ============================================================================
-- DETECCIÓN DE BACKLOG WRAP (C9)
-- ============================================================================

local function detect_backlog_wrap()
    local ok, lp = pcall(EntityCache.GetLocal)
    if not ok or not lp then return false end
    
    local ok_tick, tickbase = pcall(lp.get_prop_int, lp, "CBasePlayer", "m_nTickBase")
    if not ok_tick or not tickbase then return false end
    
    local ok_interval, interval = pcall(GlobalVars.interval_per_tick)
    if not ok_interval or not interval then return false end
    
    -- Calcular curtime actual
    local current_curtime = tickbase * interval
    
    -- Detectar salto hacia atrás mayor a 1.0 segundos
    if last_curtime > 0 and (last_curtime - current_curtime) > 1.0 then
        wrap_detected = true
        last_curtime = current_curtime
        return true
    end
    
    last_curtime = current_curtime
    wrap_detected = false
    return false
end

-- ============================================================================
-- HOOKS: on_cl_move_pre Y on_create_move
-- ============================================================================
-- Aplicamos en AMBOS callbacks para asegurar que el permachoke no se pierda
-- si Echidna/RapidFire reescribe los valores de red

function on_cl_move_pre()
    if _G.echidna_lavender_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    -- Detección de wrap (solo para telemetría, no corta el permachoke)
    detect_backlog_wrap()

    -- Aplicar exploit base SIEMPRE (permachoke + choke 3 + gate 1)
    apply_base_exploit()

    -- Si el toggle C está activo, aplicar choke burst (20) en lugar del base (3)
    if choke_burst_enabled then
        local netchan, client_state_ptr = get_netchan_and_client_state()
        if client_state_ptr then
            write_int_safe(client_state_ptr + 19024, CFG.choke_burst)
        end
    end
end

function on_create_move(cmd, lp)
    if _G.echidna_lavender_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    -- Reaplicar en cada usercmd para asegurar que no se pierda
    apply_base_exploit()

    if choke_burst_enabled then
        local netchan, client_state_ptr = get_netchan_and_client_state()
        if client_state_ptr then
            write_int_safe(client_state_ptr + 19024, CFG.choke_burst)
        end
    end
end

-- ============================================================================
-- TOGGLE CON TECLA C
-- ============================================================================

function on_key_down(key)
    if key == VK_C and not key_held then
        key_held = true
        choke_burst_enabled = not choke_burst_enabled
        
        pcall(client.print, "[Lavender] Choke Burst " .. (choke_burst_enabled and "ON (20)" or "OFF (3)") .. " | Permachoke SIEMPRE ACTIVO")
    end
end

function on_key_up(key)
    if key == VK_C then
        key_held = false
    end
end

-- ============================================================================
-- UI EN PANTALLA
-- ============================================================================

function on_end_scene()
    if _G.echidna_lavender_instance ~= INSTANCE then return end
    
    local dl = imgui.get_foreground_draw_list()
    if not dl then return end
    
    local x = CFG.ui_x
    local y = CFG.ui_y
    
    -- Texto principal: ON/OFF se refiere al choke burst (20), no al permachoke
    local text = choke_burst_enabled and "Lavender [ON]" or "Lavender [OFF]"
    
    -- Fondo semi-transparente
    dl:add_rect_filled(x - 5, y - 3, x + 150, y + 17, 0.05, 0.05, 0.08, 0.70, 4)
    
    -- Línea decorativa lavanda a la izquierda
    dl:add_rect_filled(x - 5, y - 3, x - 2, y + 17, CFG.ui_color[1], CFG.ui_color[2], CFG.ui_color[3], 1.0, 2)
    
    -- Texto principal en color lavanda
    dl:add_text(x + 2, y, CFG.ui_color[1], CFG.ui_color[2], CFG.ui_color[3], CFG.ui_color[4], text)
    
    -- Indicador de wrap si se detectó
    if wrap_detected then
        dl:add_text(x + 2, y + 18, 1.0, 0.3, 0.3, 1.0, "[WRAP DETECTED]")
    end
end

-- ============================================================================
-- DESCARGA SEGURA
-- ============================================================================

function on_unload()
    choke_burst_enabled = false
    restore_network_state()
    genuine_ack = nil
    genuine_choked = nil
    last_curtime = -1.0
    client.print("[Lavender] Descargado. Red restaurada a estado genuino.")
end

client.print("[Lavender] Cargado. Permachoke + Choke(3) + Gate1 SIEMPRE ACTIVOS.")
client.print("[Lavender] Presiona 'C' para toggle Choke Burst(20).")
