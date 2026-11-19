local ffi = require("ffi")
pcall(ffi.cdef, [[ void* GetModuleHandleA(const char* lpModuleName); ]])

local engine = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))

local function read_u32(addr)
    if not addr or addr < 0x10000 then return nil end
    local ok, val = pcall(function() return ffi.cast("uint32_t*", addr)[0] end)
    return ok and tonumber(val) or nil
end

local function read_i32(addr)
    if not addr or addr < 0x10000 then return nil end
    local ok, val = pcall(function() return ffi.cast("int32_t*", addr)[0] end)
    return ok and tonumber(val) or nil
end

local last_print = 0

function on_create_move(cmd, lp)
    if not EngineClient.IsInGame() then return end
    local now = os.clock()
    if now - last_print < 0.3 then return end
    last_print = now

    local cs = read_u32(engine + 4352236)
    if not cs or cs < 0x10000 then
        client.print("[DIAG] client_state no resuelto")
        return
    end

    local nc = read_u32(cs + 24)
    local choked_raw = read_i32(cs + 19024)

    local line = string.format("[DIAG] cs=0x%X nc=0x%X choked_raw(+19024)=%s",
        cs, nc or 0, tostring(choked_raw))

    if nc and nc > 0x10000 and nc < 0xFFFFFFFF then
        local ack = read_i32(nc + 16)
        local chk = read_i32(nc + 28)
        line = line .. string.format(" | ack(+16)=%s chk(+28)=%s", tostring(ack), tostring(chk))
    end

    local ok, info = pcall(EngineClient.GetNetChannelInfo)
    if ok and info and not info:IsNull() then
        local a = info:GetAvgChoke(0) or -1
        line = line .. string.format(" | API avgChoke=%.3f", a)
    end

    client.print(line)
end
