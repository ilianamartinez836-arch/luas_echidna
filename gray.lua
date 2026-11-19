-- World Graygrid / Texture Override — Echidna (L4D2)
-- Reemplaza texturas del mundo por dev/graygrid
local ffi = require("ffi")

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    void* GetProcAddress(void* hModule, const char* lpProcName);
]])

local function log(msg)
    pcall(client.print, "[Graygrid] " .. tostring(msg))
end

-- 1. Obtener interfaz VMaterialSystem080
local matsys_dll = ffi.C.GetModuleHandleA("materialsystem.dll")
if not matsys_dll or ffi.cast("uintptr_t", matsys_dll) == 0 then
    log("Error: materialsystem.dll no encontrado.")
    return
end

local ci_raw = ffi.C.GetProcAddress(matsys_dll, "CreateInterface")
if not ci_raw then
    log("Error: CreateInterface no encontrado.")
    return
end

local ci = ffi.cast("void*(__cdecl*)(const char*, int*)", ci_raw)
local mat_system = ci("VMaterialSystem080", nil)

if not mat_system or ffi.cast("uintptr_t", mat_system) < 0x10000 then
    log("Error: No se pudo obtener la interfaz VMaterialSystem080.")
    return
end

local vtable = ffi.cast("uintptr_t**", mat_system)[0]

-- En L4D2 FindMaterial es el slot 71 (o 72 segun build)
-- Verificamos el slot 71 primero
local FIND_MATERIAL_SLOT = 71
local target_fn = vtable[FIND_MATERIAL_SLOT]

log(string.format("VMaterialSystem080: 0x%X | Hookeando Slot %d: 0x%X",
    tonumber(ffi.cast("uintptr_t", mat_system)),
    FIND_MATERIAL_SLOT,
    tonumber(target_fn)
))

local hook_find_mat = nil

local ok, err = pcall(function()
    hook_find_mat = hooks.create(
        target_fn,
        "void*(__thiscall*)(void*, const char*, const char*, bool, const char*)",
        function(orig, thisptr, mat_name, group_name, make_default, complain_prefix)
            if mat_name and ffi.cast("uintptr_t", mat_name) > 0x10000 then
                local s_mat = ffi.string(mat_name)
                
                -- Evitar bucle si ya es dev/graygrid
                if s_mat ~= "dev/graygrid" and group_name and ffi.cast("uintptr_t", group_name) > 0x10000 then
                    local s_group = ffi.string(group_name)
                    if string.find(s_group, "World textures") then
                        return orig(thisptr, "dev/graygrid", group_name, make_default, complain_prefix)
                    end
                end
            end

            return orig(thisptr, mat_name, group_name, make_default, complain_prefix)
        end
    )
end)

if ok and hook_find_mat then
    log("Hook aplicado con exito. Recarga el mapa o inicia partida para ver el cambio.")
else
    log("Error al crear el hook: " .. tostring(err))
end

function on_unload()
    if hook_find_mat then
        pcall(function() hook_find_mat:destroy() end)
        hook_find_mat = nil
    end
    memory.restore_all()
    log("Descargado.")
end
