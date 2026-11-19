-- ChokeExploit 2 (ByxStorm Port 1:1) — Echidna (L4D2)
-- Segunda instancia independiente — Activo permanentemente
local ffi = require("ffi")

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
]])

local CHOKE_VALUE_2 = 45

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

local function apply_choke_exploit_2()
    local client_state_ptr = read_int(engine + 4352236)
    if not client_state_ptr or client_state_ptr == 0 then return end

    -- Escribir Choked_Commands en client_state + 19024
    write_int_safe(client_state_ptr + 19024, CHOKE_VALUE_2)

    -- Spoof de NetChannel (client_state + 24)
    local netchan = read_int(client_state_ptr + 24)
    if not netchan or netchan == 0 then return end

    write_int_safe(netchan + 16, -1)
    write_int_safe(netchan + 28, 255)
end

function on_cl_move_pre()
    apply_choke_exploit_2()
end

function on_create_move(cmd, lp)
    apply_choke_exploit_2()
end

function on_unload()
    local client_state_ptr = read_int(engine + 4352236)
    if client_state_ptr and client_state_ptr > 0 then
        write_int_safe(client_state_ptr + 19024, 0)
    end
    client.print("[ChokeExploit 2] Descargado y reseteado a 0.")
end

client.print("[ChokeExploit 2] Cargado — Instancia 2 activa permanentemente (Valor: " .. CHOKE_VALUE_2 .. ").")
