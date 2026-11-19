local ffi = require("ffi")

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
]])

local PAGE_EXECUTE_READWRITE = 0x40

local CFG = {
    enabled = false,
    choke_value = 3,
    key_toggle = 0x43,
    ui_x = 150,
    ui_y = 20,
    ui_color = {180/255, 130/255, 255/255, 1.0},
}

local INSTANCE = {}
_G.echidna_lavender_instance = INSTANCE

local engine_base = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))
local genuine_ack = nil
local genuine_choked = nil
local last_curtime = -1.0
local wrap_detected = false

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

local function apply_network_manipulation()
    if not engine_base or engine_base == 0 then return false end

    local client_state_ptr = read_int(engine_base + 4352236)
    if not client_state_ptr or client_state_ptr == 0 then return false end

    local netchan = read_int(client_state_ptr + 24)
    if not netchan or netchan == 0 then 
        local ok, nc_info = pcall(EngineClient.GetNetChannelInfo)
        if ok and nc_info and not nc_info:IsNull() then
            local ptr = nc_info:GetPtr()
            if ptr then netchan = tonumber(ffi.cast("uintptr_t", ptr)) end
        end
    end
    if not netchan or netchan == 0 then return false end

    if genuine_ack == nil then
        local cur_ack = read_int(netchan + 16)
        local cur_choked = read_int(netchan + 28)
        if cur_ack and cur_ack ~= -1 then
            genuine_ack = cur_ack
            genuine_choked = cur_choked or 0
        end
    end

    write_double_safe(netchan + 184, 0.0)
    write_int_safe(client_state_ptr + 19024, CFG.choke_value)
    write_int_safe(netchan + 16, -1)
    write_int_safe(netchan + 28, 255)

    return true
end

local function restore_network_state()
    local client_state_ptr = read_int(engine_base + 4352236)
    if not client_state_ptr or client_state_ptr == 0 then return end
    local netchan = read_int(client_state_ptr + 24)
    if not netchan or netchan == 0 then return end

    local cur_ack = read_int(netchan + 16)
    local cur_choked = read_int(netchan + 28)

    if cur_ack == -1 and genuine_ack ~= nil then
        write_int_safe(netchan + 16, genuine_ack)
    end
    if cur_choked == 255 and genuine_choked ~= nil then
        write_int_safe(netchan + 28, genuine_choked)
    end

    write_int_safe(client_state_ptr + 19024, 0)
end

local function detect_backlog_wrap()
    local ok, lp = pcall(EntityCache.GetLocal)
    if not ok or not lp then return false end
    
    local ok_tick, tickbase = pcall(lp.get_prop_int, lp, "CBasePlayer", "m_nTickBase")
    if not ok_tick or not tickbase then return false end
    
    local ok_interval, interval = pcall(GlobalVars.interval_per_tick)
    if not ok_interval or not interval then return false end
    
    local current_curtime = tickbase * interval
    
    if last_curtime > 0 and (last_curtime - current_curtime) > 1.0 then
        wrap_detected = true
        last_curtime = current_curtime
        return true
    end
    
    last_curtime = current_curtime
    wrap_detected = false
    return false
end

function on_cl_move_pre()
    if _G.echidna_lavender_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    if detect_backlog_wrap() then
        return
    end

    if CFG.enabled then
        apply_network_manipulation()
    else
        restore_network_state()
        genuine_ack = nil
        genuine_choked = nil
    end
end

function on_key_down(key)
    if key == CFG.key_toggle then
        CFG.enabled = not CFG.enabled
        pcall(client.print, "[Lavender] " .. (CFG.enabled and "ACTIVADO" or "DESACTIVADO"))
        
        if not CFG.enabled then
            genuine_ack = nil
            genuine_choked = nil
            restore_network_state()
        end
    end
end

function on_end_scene()
    if _G.echidna_lavender_instance ~= INSTANCE then return end
    
    local dl = imgui.get_foreground_draw_list()
    if not dl then return end
    
    local x = CFG.ui_x
    local y = CFG.ui_y
    local text = CFG.enabled and "Lavender [ON]" or "Lavender [OFF]"
    
    dl:add_rect_filled(x - 5, y - 3, x + 150, y + 17, 0.05, 0.05, 0.08, 0.70, 4)
    dl:add_rect_filled(x - 5, y - 3, x - 2, y + 17, CFG.ui_color[1], CFG.ui_color[2], CFG.ui_color[3], 1.0, 2)
    dl:add_text(x + 2, y, CFG.ui_color[1], CFG.ui_color[2], CFG.ui_color[3], CFG.ui_color[4], text)
    
    if wrap_detected then
        dl:add_text(x + 2, y + 18, 1.0, 0.3, 0.3, 1.0, "[WRAP DETECTED]")
    end
end

function on_unload()
    CFG.enabled = false
    restore_network_state()
    genuine_ack = nil
    genuine_choked = nil
    last_curtime = -1.0
    client.print("[Lavender] Descargado. Red restaurada a estado genuino.")
end

client.print("[Lavender] Cargado. Presiona 'C' para activar/desactivar.")
client.print("[Lavender] Configuración óptima para HvH: Choke=" .. CFG.choke_value)




