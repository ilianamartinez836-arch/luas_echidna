-- Memory Probe: Network & ClientState Scanner (Solo Lectura) — Echidna (L4D2)
-- Presiona F9 para hacer una captura de memoria en la consola
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_probe_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    short GetAsyncKeyState(int vKey);
]])

local VK_DUMP_KEY = 0x78 -- Tecla F9

local engine_base = ffi.cast("uintptr_t", ffi.C.GetModuleHandleA("engine.dll"))

local function read_i32(addr)
    if not addr or addr < 0x10000 then return 0 end
    local ok, val = pcall(function() return ffi.cast("int32_t*", addr)[0] end)
    return ok and val or 0
end

local function read_u8(addr)
    if not addr or addr < 0x10000 then return 0 end
    local ok, val = pcall(function() return ffi.cast("uint8_t*", addr)[0] end)
    return ok and val or 0
end

local function read_double(addr)
    if not addr or addr < 0x10000 then return 0.0 end
    local ok, val = pcall(function() return ffi.cast("double*", addr)[0] end)
    return ok and val or 0.0
end

local function read_float(addr)
    if not addr or addr < 0x10000 then return 0.0 end
    local ok, val = pcall(function() return ffi.cast("float*", addr)[0] end)
    return ok and val or 0.0
end

local function dump_network_memory()
    if not engine_base or engine_base == 0 then
        client.print("[PROBE] Error: engine.dll no encontrado.")
        return
    end

    if not EngineClient.IsInGame() then
        client.print("[PROBE] Entra a una partida antes de presionar F9.")
        return
    end

    local raw_cs_ptr = read_i32(engine_base + 4352236)
    if not raw_cs_ptr or raw_cs_ptr < 0x10000 then
        client.print("[PROBE] Error: No se pudo resolver client_state.")
        return
    end

    local netchan_ptr = read_i32(raw_cs_ptr + 24)

    client.print("==================================================")
    client.print("         L4D2 CLIENT_STATE & NETCHAN PROBE        ")
    client.print("==================================================")
    client.print(string.format("engine.dll Base    : 0x%X", tonumber(engine_base)))
    client.print(string.format("client_state Raw   : 0x%X", raw_cs_ptr))
    client.print(string.format("Connection State   : %d (offset +104, 6=InGame)", read_i32(raw_cs_ptr + 104)))
    client.print(string.format("Next Sample Time   : %.4f (offset +112 double)", read_double(raw_cs_ptr + 112)))
    client.print("--------------------------------------------------")
    client.print(">> BLOQUE DE COMANDOS Y CHOKE (19000 - 19056):")

    for off = 19008, 19056, 4 do
        local val_i32 = read_i32(raw_cs_ptr + off)
        local b0 = read_u8(raw_cs_ptr + off)
        local b1 = read_u8(raw_cs_ptr + off + 1)
        local b2 = read_u8(raw_cs_ptr + off + 2)
        local b3 = read_u8(raw_cs_ptr + off + 3)

        local tag = ""
        if off == 19012 then tag = " [m_nLastOutgoing? v4+19012]"
        elseif off == 19016 then tag = " [Choked v4+19016]"
        elseif off == 19020 then tag = " [nLastOutgoing raw]"
        elseif off == 19024 then tag = " [Choked_Commands raw]"
        elseif off == 19036 then tag = " [FORCECHOKE / bNoSend v4]"
        elseif off == 19044 then tag = " [FORCECHOKE raw?]"
        end

        client.print(string.format("  +%-5d: %-10d | HEX: 0x%-8X | Bytes: [%02X %02X %02X %02X]%s",
            off, val_i32, val_i32, b0, b1, b2, b3, tag))
    end

    client.print("--------------------------------------------------")
    if netchan_ptr and netchan_ptr > 0x10000 then
        client.print(string.format("NetChannel Ptr     : 0x%X (offset +24)", netchan_ptr))
        client.print(string.format("m_nOutSequenceNr   : %d (netchan + 8)", read_i32(netchan_ptr + 8)))
        client.print(string.format("m_nOutSeqNrAck     : %d (netchan + 16)", read_i32(netchan_ptr + 16)))
        client.print(string.format("m_nChokedPackets   : %d (netchan + 28)", read_i32(netchan_ptr + 28)))
        client.print(string.format("m_fClearTime (f32) : %.4f (netchan + 0xB8)", read_float(netchan_ptr + 0xB8)))
        client.print(string.format("m_fClearTime (f64) : %.4f (netchan + 0xB8)", read_double(netchan_ptr + 0xB8)))
    else
        client.print("NetChannel         : No encontrado o nulo.")
    end
    client.print("==================================================")
end

function on_key_down(key)
    if key == VK_DUMP_KEY then
        pcall(dump_network_memory)
    end
end

function on_unload()
    client.print("[PROBE] Descargado.")
end

client.print("[PROBE] Cargado con exito. Entra a una partida y presiona F9.")
