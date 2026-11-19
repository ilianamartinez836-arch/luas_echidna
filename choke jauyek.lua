-- Choke NOP (Heaven -> Echidna Port 1:1)
-- Manten presionada la F para chokear a 120
local ffi = require("ffi")

pcall(ffi.cdef, [[
    short GetAsyncKeyState(int vKey);
]])

local KEY_F            = 0x46      -- Tecla F
local CHOKED_VALUE     = 200       -- Mismo valor de 120 de Heaven
local ENGINE_CS_OFF    = 4352236   -- 0x4268EC
local CS_CHOKED_OFF    = 19024

local NOP_PATTERN      = "85 C0 7E ?? 0F B6 C8"
local NOP_BYTES        = 4

local client_state     = nil
local patch_address    = nil
local orig_bytes_str   = nil

local function log(msg)
    pcall(client.print, "[choke_nop] " .. tostring(msg))
end

-- 1. Resolver client_state igual que en Heaven
local function resolve_client_state()
    local eng = memory.get_module_base("engine.dll")
    if not eng or eng == 0 then return false end

    local ok, cs = pcall(memory.read_i32, eng + ENGINE_CS_OFF)
    if not ok or not cs or cs == 0 then return false end

    client_state = cs
    log(string.format("client_state = 0x%X", cs))
    return true
end

-- 2. Aplicar parche NOP (4 bytes 0x90)
local function apply_nop_patch()
    local addr = memory.find_pattern("engine.dll", NOP_PATTERN)
    if not addr or addr == 0 then
        log("Error: pattern NOP no encontrado")
        return false
    end

    patch_address = addr

    -- Guardar bytes originales para restaurar
    orig_bytes_str = memory.read_bytes(addr, NOP_BYTES)

    -- Aplicar 4 NOPs (0x90, 0x90, 0x90, 0x90)
    local nops = string.char(0x90, 0x90, 0x90, 0x90)
    local ok = memory.patch(addr, nops)

    if ok then
        log(string.format("NOP patch aplicado @ 0x%X (4 bytes)", addr))
        return true
    else
        log("Fallo al aplicar memory.patch")
        return false
    end
end

-- Inicializar al cargar
resolve_client_state()
apply_nop_patch()

local function is_f_down()
    return bit.band(ffi.C.GetAsyncKeyState(KEY_F), 0x8000) ~= 0
end

-- 3. Inyeccion en CreateMove
function on_create_move(cmd, lp)
    if not cmd then return end
    if not EngineClient.IsInGame() then return end

    if not client_state then
        if not resolve_client_state() then return end
    end

    -- Si F esta apretado, escribir los 120 de choke directo al motor
    if is_f_down() then
        pcall(memory.write_i32, client_state + CS_CHOKED_OFF, CHOKED_VALUE)
    end
end

-- 4. Restauracion en Unload
function on_unload()
    if patch_address and orig_bytes_str then
        pcall(memory.patch, patch_address, orig_bytes_str)
        log("NOP patch restaurado")
    end
    if client_state then
        pcall(memory.write_i32, client_state + CS_CHOKED_OFF, 0)
    end
    patch_address = nil
    client_state = nil
    log("unloaded")
end

log("loaded — F apretado = choked=" .. CHOKED_VALUE)

