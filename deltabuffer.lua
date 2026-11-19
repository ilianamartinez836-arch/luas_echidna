-- WriteUsercmdDeltaToBuffer (WUD) Choke / Delta Exploit — Echidna (L4D2)
-- Puerto inteligente y blindado del script de Aimware (Cero crashes)
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_wud_safe_instance = INSTANCE

pcall(ffi.cdef, [[
    void* GetModuleHandleA(const char* lpModuleName);
    void* GetProcAddress(void* hModule, const char* lpProcName);

    typedef struct {
        uint8_t*    pData;
        int         nDataBytes;
        int         nDataBits;
        int         iCurBit;
        bool        bOverflow;
        bool        bAssertOnOverflow;
        const char* pDebugName;
    } bf_write_t;

    typedef bool(__fastcall* WUD_fn)(
        void* thisptr,
        void* edx,
        int   nSlot,
        void* buf,
        int   from,
        int   to,
        bool  isnewcommand
    );
]])

local function log(msg)
    pcall(client.print, "[WUD-Choke] " .. tostring(msg))
end

-- 1. Obtener interfaz VClient016 (La estándar de L4D2)
local clientDll = ffi.C.GetModuleHandleA("client.dll")
if not clientDll or ffi.cast("uintptr_t", clientDll) == 0 then
    log("Error: client.dll no encontrado.")
    return
end

local ci_raw = ffi.C.GetProcAddress(clientDll, "CreateInterface")
if not ci_raw then
    log("Error: CreateInterface no encontrado.")
    return
end

local ci = ffi.cast("void*(__cdecl*)(const char*, int*)", ci_raw)
local baseClient = nil

for _, version in ipairs({ "VClient016", "VClient017", "VClient015" }) do
    local ptr = ci(version, nil)
    if ptr ~= nil and ffi.cast("uintptr_t", ptr) > 0x10000 then
        baseClient = ptr
        break
    end
end

if not baseClient or ffi.cast("uintptr_t", baseClient) == 0 then
    log("Error crítico: baseClient es nulo.")
    return
end

-- 2. Resolver VTable Slot 23 (WriteUsercmdDeltaToBuffer en L4D2)
local vtable = ffi.cast("uintptr_t**", baseClient)[0]
local pWUD = ffi.cast("WUD_fn", vtable[23])

-- 3. Estado, buffer y variables
local CHOKE_MAX  = 14
local chokeTick  = 0
local lastTo     = -1

local raw_buf = ffi.new("uint8_t[2048]")
local bfw     = ffi.new("bf_write_t")

-- 4. Ejecución en CreateMove
function on_create_move(cmd, lp)
    if _G.echidna_wud_safe_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() or not cmd then
        lastTo = -1
        chokeTick = 0
        return
    end

    local to = cmd:get_tick_count()
    if not to or to <= 0 then
        pcall(function() to = GlobalVars.tickcount() end)
    end
    if not to or to <= 0 then return end

    if lastTo == -1 then
        lastTo = to - 1
    end

    chokeTick = chokeTick + 1
    if chokeTick <= CHOKE_MAX then
        return
    end
    chokeTick = 0

    bfw.pData             = raw_buf
    bfw.nDataBytes        = 2048
    bfw.nDataBits         = 2048 * 8
    bfw.iCurBit           = 0
    bfw.bOverflow         = false
    bfw.bAssertOnOverflow = false
    bfw.pDebugName        = "Echidna_WUD_Buffer"

    local ok, res = pcall(pWUD, baseClient, nil, 0, ffi.cast("void*", bfw), lastTo, to, true)
    if not ok then
        log("Error en vtable WUD: " .. tostring(res))
    end

    lastTo = to
end

function on_unload()
    lastTo = -1
    chokeTick = 0
    log("Descargado con éxito.")
end

log("Cargado — WUD Delta Choke blindado (Slot 23) listo.")
