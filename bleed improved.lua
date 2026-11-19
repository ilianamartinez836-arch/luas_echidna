-- BleedExploit Improved (Toggle 'H' + On-Screen Lavender Watermark) — Echidna (L4D2)
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_bleed_improved_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
    short GetAsyncKeyState(int vKey);
]])

local PAGE_EXECUTE_READWRITE = 0x40

-- =========================================================================
-- CONFIGURACION
-- =========================================================================
local TOGGLE_KEY  = 0x48  -- Tecla 'H' (0x48)
local BLEED_VALUE = 70

-- Color Lavanda / Purpura suave
local COLOR_LAVENDER = { 0.765, 0.608, 1.000, 1.0 }

local active    = false
local key_held  = false

local engine = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))
if not engine or engine == 0 then return end

local function read_int(addr)
    if not addr or addr < 0x10000 then return nil end
    local ok, val = pcall(function() return ffi.cast("int*", addr)[0] end)
    return ok and val or nil
end

local function write_int_safe(addr, val)
    if not addr or addr < 0x10000 then return false end
    local old_protect = ffi.new("unsigned long[1]")
    if ffi.C.VirtualProtect(ffi.cast("void*", addr), 4, 0x40, old_protect) ~= 0 then
        local ok = pcall(function() ffi.cast("int*", addr)[0] = val end)
        ffi.C.VirtualProtect(ffi.cast("void*", addr), 4, old_protect[0], old_protect)
        return ok
    end
    return false
end

-- =========================================================================
-- CAPTURA DE ESTADO GENUINO (SINGLE RESTORE OWNER)
-- =========================================================================
local genuine_ack   = nil
local genuine_chok  = nil

local function apply_bleed_improved()
    local client_state_ptr = read_int(engine + 4352236)
    if not client_state_ptr or client_state_ptr == 0 then return end

    local netchan = read_int(client_state_ptr + 24)
    if not netchan or netchan == 0 then return end

    -- Capturar valores reales antes de sobreescribir
    if not genuine_ack then
        local cur_ack = read_int(netchan + 16)
        local cur_chk = read_int(netchan + 28)
        if cur_ack and cur_ack ~= -1 then
            genuine_ack  = cur_ack
            genuine_chok = cur_chk
        end
    end

    if active then
        -- 1. Escribir Choked_Commands = 45 en client_state + 19024
        write_int_safe(client_state_ptr + 19024, BLEED_VALUE)

        -- 2. Spoof de NetChannel
        write_int_safe(netchan + 16, -1)
        write_int_safe(netchan + 28, 255)
    else
        -- Al desactivar: volver a 0
        write_int_safe(client_state_ptr + 19024, 0)
    end
end

-- =========================================================================
-- TOGGLE CON LA TECLA 'H'
-- =========================================================================
function on_key_down(key)
    if key == TOGGLE_KEY and not key_held then
        key_held = true
        active = not active
        pcall(client.print, "[BleedImproved] " .. (active and "ACTIVADO" or "DESACTIVADO"))
    end
end

function on_key_up(key)
    if key == TOGGLE_KEY then
        key_held = false
    end
end

function on_cl_move_pre()
    if _G.echidna_bleed_improved_instance ~= INSTANCE then return end
    apply_bleed_improved()
end

function on_create_move(cmd, lp)
    if _G.echidna_bleed_improved_instance ~= INSTANCE then return end
    apply_bleed_improved()
end

-- =========================================================================
-- INDICADOR EN PANTALLA (TEXTO COLOR LAVANDA EN EL LADO IZQUIERDO MEDIO)
-- =========================================================================
function on_end_scene()
    if _G.echidna_bleed_improved_instance ~= INSTANCE then return end

    local sw, sh = 1920, 1080
    pcall(function()
        local w_s, h_s = EngineClient.GetScreenSize()
        if w_s and w_s > 0 then sw, sh = w_s, h_s end
    end)

    -- Posicion: Lado izquierdo, a la mitad de altura, un poco adelantado (x = 35)
    local x = 35
    local y = math.floor(sh * 0.48)

    local status_str = active and "ON" or "OFF"
    local text = string.format("Bleed Improved: %s (%d)", status_str, BLEED_VALUE)

    local dl = imgui.get_foreground_draw_list()
    local tw = imgui.CalcTextSize(text)

    -- Fondo oscuro para legibilidad
    dl:add_rect_filled(x - 6, y - 3, x + tw + 6, y + 17, 0.05, 0.05, 0.08, 0.70, 4)
    -- Pequeña linea decorativa lavanda a la izquierda
    dl:add_rect_filled(x - 6, y - 3, x - 3, y + 17, COLOR_LAVENDER[1], COLOR_LAVENDER[2], COLOR_LAVENDER[3], 1.0, 2)
    -- Texto en color Lavanda
    dl:add_text(x + 2, y, COLOR_LAVENDER[1], COLOR_LAVENDER[2], COLOR_LAVENDER[3], COLOR_LAVENDER[4], text)
end

-- =========================================================================
-- DESCARGA SEGURA
-- =========================================================================
function on_unload()
    active = false

    local client_state_ptr = read_int(engine + 4352236)
    if client_state_ptr and client_state_ptr > 0 then
        write_int_safe(client_state_ptr + 19024, 0)

        local netchan = read_int(client_state_ptr + 24)
        if netchan and netchan > 0 then
            if genuine_ack and genuine_ack ~= -1 then
                write_int_safe(netchan + 16, genuine_ack)
            end
            if genuine_chok and genuine_chok ~= 255 then
                write_int_safe(netchan + 28, genuine_chok)
            end
        end
    end

    genuine_ack  = nil
    genuine_chok = nil
    client.print("[BleedExploit Improved] Descargado — Red restaurada.")
end

client.print("[BleedExploit Improved] Cargado — Presiona 'H' para alternar (Texto Lavanda en pantalla).")


