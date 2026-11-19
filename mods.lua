-- Vanilla Bypass (Echidna L4D2)
-- Fuerza client-side vanilla = 0 en engine.dll
local ffi = require("ffi")

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int   VirtualProtect(void* lpAddress, size_t dwSize, uint32_t flNewProtect, uint32_t* lpflOldProtect);
]])

local PAGE_EXECUTE_READWRITE = 0x40

local function log(msg)
    pcall(client.print, "[VANILLA] " .. tostring(msg))
end

local engine_base = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))
if not engine_base or engine_base == 0 then
    log("Error: engine.dll no encontrado.")
    return
end

local PATCH_OFFSET = 0x5596C  
local patch_addr   = ffi.cast("uint8_t*", engine_base + PATCH_OFFSET)

-- Verificar que los bytes coincidan antes de parchar para evitar crashes
local b0, b1, b2, b3 = patch_addr[0], patch_addr[1], patch_addr[2], patch_addr[3]
if b0 ~= 0x0F or b1 ~= 0xB6 or b2 ~= 0x4F or b3 ~= 0x5D then
    log(string.format("Error: Bytes no coinciden (%02X %02X %02X %02X). Offset incorrecto.", b0, b1, b2, b3))
    return
end

-- Guardar bytes originales para restaurar
local orig_bytes = ffi.new("uint8_t[4]")
for i = 0, 3 do orig_bytes[i] = patch_addr[i] end

-- Aplicar parche: xor ecx, ecx ; nop ; nop
local old_prot = ffi.new("uint32_t[1]")
if ffi.C.VirtualProtect(patch_addr, 4, PAGE_EXECUTE_READWRITE, old_prot) ~= 0 then
    patch_addr[0] = 0x31  
    patch_addr[1] = 0xC9  
    patch_addr[2] = 0x90 
    patch_addr[3] = 0x90  
    ffi.C.VirtualProtect(patch_addr, 4, old_prot[0], old_prot)
    log("Parche aplicado con exito (vanilla forzado a 0).")
else
    log("Error al modificar proteccion de memoria.")
    return
end

_G.echidna_vanilla_patch = { addr = patch_addr, orig = orig_bytes }

function on_unload()
    local g = _G.echidna_vanilla_patch
    if not g then return end

    local old_prot2 = ffi.new("uint32_t[1]")
    if ffi.C.VirtualProtect(g.addr, 4, PAGE_EXECUTE_READWRITE, old_prot2) ~= 0 then
        for i = 0, 3 do g.addr[i] = g.orig[i] end
        ffi.C.VirtualProtect(g.addr, 4, old_prot2[0], old_prot2)
        log("Descargado: bytes originales restaurados.")
    end
    _G.echidna_vanilla_patch = nil
end
