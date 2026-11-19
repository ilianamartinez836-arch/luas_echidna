-- Opcion 3: Hibrido de Red Total
local ffi = require("ffi")
pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    int VirtualProtect(void* lpAddress, size_t dwSize, unsigned long flNewProtect, unsigned long* lpflOldProtect);
]])
local engine = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))

local function apply_perma()
    if not EngineClient.IsInGame() then return end
    local cs = ffi.cast("int*", engine + 4352236)[0]
    if not cs or cs < 0x10000 then return end
    local nc = ffi.cast("int*", cs + 24)[0]
    if not nc or nc < 0x10000 then
        local ok, info = pcall(EngineClient.GetNetChannelInfo)
        if ok and info and not info:IsNull() then
            local p = info:GetPtr()
            if p then nc = tonumber(ffi.cast("uintptr_t", p)) end
        end
    end
    if not nc or nc < 0x10000 then return end

    local old = ffi.new("unsigned long[1]")
    if ffi.C.VirtualProtect(ffi.cast("void*", nc + 16), 16, 0x40, old) ~= 0 then
        ffi.cast("int*", nc + 16)[0] = -1
        ffi.cast("int*", nc + 28)[0] = 255
        ffi.C.VirtualProtect(ffi.cast("void*", nc + 16), 16, old[0], old)
    end
end

function on_cl_move_pre() apply_perma() end
function on_end_scene() apply_perma() end
