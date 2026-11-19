-- Movement Recorder (ByxStorm C++ Port 1:1) — Echidna (L4D2)
-- Graba, reproduce, detecta desvio, checkpoints automaticos y guarda por mapa
local ffi = require("ffi")

local INSTANCE = {}
_G.echidna_recorder_instance = INSTANCE

pcall(ffi.cdef, [[
    short GetAsyncKeyState(int vKey);
]])

-- =========================================================================
-- CONFIGURACION (MovementRecorder.h)
-- =========================================================================
local CFG = {
    checkpoint_interval  = 14,     -- Checkpoint cada 14 frames
    resume_distance      = 100.0,  -- Radio para reanudar desde un checkpoint
    deviation_threshold  = 150.0,  -- Si te desvias mas de 150u, devuelve control manual
    show_path            = true,
    show_checkpoints     = true,
    show_status          = true,
}

-- Teclas nativas de ByxStorm:
local KEY_RECORD  = 0x74 -- F5
local KEY_PLAY    = 0x75 -- F6
local KEY_LOAD    = 0x76 -- F7
local KEY_SAVE    = 0x77 -- F8
local KEY_RESUME  = 0x52 -- 'R'

-- =========================================================================
-- ESTADO INTERNO
-- =========================================================================
local STATE_IDLE      = 0
local STATE_RECORDING = 1
local STATE_PLAYING   = 2

local current_state   = STATE_IDLE
local manual_override = false
local current_frame   = 1

local frames          = {} -- Array de frames grabados
local checkpoints     = {} -- Array de puntos de control { frame_idx, pos }

local key_latch = {
    [KEY_RECORD] = false,
    [KEY_PLAY]   = false,
    [KEY_LOAD]   = false,
    [KEY_SAVE]   = false,
}

local function log(msg)
    pcall(client.print, "[Recorder] " .. tostring(msg))
end

local function is_key_down(vk)
    return bit.band(ffi.C.GetAsyncKeyState(vk), 0x8000) ~= 0
end

local function dist_3d(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function w2s(x, y, z)
    local p = visual.world_to_screen(x, y, z)
    if p and (p.x or p[1]) then
        return { x = p.x or p[1], y = p.y or p[2] }
    end
    return nil
end

local function get_map_file()
    local map = "default"
    pcall(function()
        local m = EngineClient.GetLevelNameShort()
        if m and m ~= "" then map = m end
    end)
    return "C:\\Echidna-L4d2\\Scripts\\rec_" .. map .. ".dat"
end

-- =========================================================================
-- GUARDADO Y CARGA EN DISCO (POR MAPA)
-- =========================================================================
local function save_to_file()
    if #frames == 0 then
        log("No hay frames grabados para guardar.")
        return
    end

    local file_path = get_map_file()
    local f = io.open(file_path, "w")
    if not f then
        log("Error al abrir archivo para guardar.")
        return
    end

    f:write(string.format("%d\n", #frames))
    for i = 1, #frames do
        local fr = frames[i]
        f:write(string.format("%.3f %.3f %.3f %.2f %.2f %.2f %.2f %d\n",
            fr.pos.x, fr.pos.y, fr.pos.z,
            fr.ang.x, fr.ang.y,
            fr.fmove, fr.smove, fr.buttons))
    end
    f:close()
    log(string.format("Ruta guardada en disco: %s (%d frames)", file_path, #frames))
end

local function load_from_file()
    local file_path = get_map_file()
    local f = io.open(file_path, "r")
    if not f then
        log("No se encontro archivo de grabacion para este mapa: " .. file_path)
        return
    end

    local count_str = f:read("*l")
    local count = tonumber(count_str) or 0
    if count <= 0 then
        f:close()
        return
    end

    frames = {}
    checkpoints = {}

    for i = 1, count do
        local line = f:read("*l")
        if not line then break end
        local px, py, pz, ax, ay, fm, sm, btn = line:match("([%d.-]+)%s+([%d.-]+)%s+([%d.-]+)%s+([%d.-]+)%s+([%d.-]+)%s+([%d.-]+)%s+([%d.-]+)%s+([%d.-]+)")
        if px then
            local fr = {
                pos     = { x = tonumber(px), y = tonumber(py), z = tonumber(pz) },
                ang     = { x = tonumber(ax), y = tonumber(ay), z = 0 },
                fmove   = tonumber(fm),
                smove   = tonumber(sm),
                buttons = tonumber(btn),
            }
            frames[#frames + 1] = fr

            if i % CFG.checkpoint_interval == 0 or i == 1 then
                checkpoints[#checkpoints + 1] = { idx = i, pos = fr.pos }
            end
        end
    end
    f:close()
    current_frame = 1
    current_state = STATE_IDLE
    manual_override = false
    log(string.format("Ruta cargada con exito: %d frames, %d checkpoints.", #frames, #checkpoints))
end

-- =========================================================================
-- LOGICA DE ACCIONES Y TECLAS
-- =========================================================================
local function handle_hotkeys()
    -- F5: Record Toggle
    local down_rec = is_key_down(KEY_RECORD)
    if down_rec and not key_latch[KEY_RECORD] then
        if current_state == STATE_RECORDING then
            current_state = STATE_IDLE
            log(string.format("Grabacion DETENIDA. Frames totales: %d", #frames))
        else
            frames = {}
            checkpoints = {}
            current_frame = 1
            current_state = STATE_RECORDING
            manual_override = false
            log("Grabacion INICIADA (F5 para detener)...")
        end
    end
    key_latch[KEY_RECORD] = down_rec

    -- F6: Playback Toggle
    local down_play = is_key_down(KEY_PLAY)
    if down_play and not key_latch[KEY_PLAY] then
        if current_state == STATE_PLAYING then
            current_state = STATE_IDLE
            manual_override = false
            log("Reproduccion DETENIDA.")
        else
            if #frames > 0 then
                current_frame = 1
                current_state = STATE_PLAYING
                manual_override = false
                log(string.format("Reproduccion INICIADA (%d frames)...", #frames))
            else
                log("No hay frames en memoria para reproducir.")
            end
        end
    end
    key_latch[KEY_PLAY] = down_play

    -- F7: Cargar desde archivo
    local down_load = is_key_down(KEY_LOAD)
    if down_load and not key_latch[KEY_LOAD] then
        load_from_file()
    end
    key_latch[KEY_LOAD] = down_load

    -- F8: Guardar a archivo
    local down_save = is_key_down(KEY_SAVE)
    if down_save and not key_latch[KEY_SAVE] then
        save_to_file()
    end
    key_latch[KEY_SAVE] = down_save
end

-- Reanudar desde el checkpoint mas cercano si estamos desviados
local function try_resume_from_checkpoint(my_pos)
    if #checkpoints == 0 then return end
    local best_dist = CFG.resume_distance
    local best_idx  = nil

    for _, cp in ipairs(checkpoints) do
        local d = dist_3d(my_pos, cp.pos)
        if d < best_dist then
            best_dist = d
            best_idx = cp.idx
        end
    end

    if best_idx then
        current_frame = best_idx
        manual_override = false
        log(string.format("Reanudando reproduccion desde Checkpoint (Frame: %d)", best_idx))
    end
end

-- =========================================================================
-- CREATEMOVE (GRABACION / REPRODUCCION / DESVIO)
-- =========================================================================
function on_create_move(cmd, lp)
    if _G.echidna_recorder_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() or not lp or not lp:is_alive() then return end

    handle_hotkeys()

    local origin = lp:get_origin()
    if not origin then return end

    -- 1. MODO GRABACION (F5)
    if current_state == STATE_RECORDING then
        local view = cmd:get_viewangles()
        local fr = {
            pos     = { x = origin.x, y = origin.y, z = origin.z },
            ang     = { x = view.x or 0, y = view.y or 0, z = 0 },
            fmove   = cmd:get_forwardmove() or 0,
            smove   = cmd:get_sidemove() or 0,
            buttons = cmd:get_buttons() or 0,
        }
        frames[#frames + 1] = fr

        if #frames % CFG.checkpoint_interval == 0 or #frames == 1 then
            checkpoints[#checkpoints + 1] = { idx = #frames, pos = fr.pos }
        end
        return
    end

    -- 2. MODO REPRODUCCION (F6)
    if current_state == STATE_PLAYING then
        -- Comprobar si se mantiene 'R' para reanudar control
        if manual_override then
            if is_key_down(KEY_RESUME) then
                try_resume_from_checkpoint(origin)
            end
            return
        end

        if current_frame > #frames then
            current_state = STATE_IDLE
            log("Reproduccion finalizada con exito.")
            return
        end

        local fr = frames[current_frame]

        -- DETECCION DE DESVIO INTELIGENTE (ByxStorm)
        local d = dist_3d(origin, fr.pos)
        if d > CFG.deviation_threshold then
            manual_override = true
            log(string.format("DESVIO DETECTADO (%.1fu > %.1fu). Control devuelto al jugador. (Manten 'R' para reanudar)", d, CFG.deviation_threshold))
            return
        end

        -- Inyectar inputs grabados
        cmd:set_viewangles(fr.ang)
        cmd:set_forwardmove(fr.fmove)
        cmd:set_sidemove(fr.smove)
        cmd:set_buttons(fr.buttons)
        pcall(EngineClient.SetViewAngles, fr.ang)

        current_frame = current_frame + 1
    end
end

-- =========================================================================
-- VISUALIZACION 3D Y ESTADO EN PANTALLA (PAINT)
-- =========================================================================
function on_end_scene()
    if _G.echidna_recorder_instance ~= INSTANCE then return end
    if not EngineClient.IsInGame() then return end

    local dl = imgui.get_foreground_draw_list()

    -- 1. DIBUJAR CAMINO 3D EN EL SUELO
    if CFG.show_path and #frames > 1 then
        for i = 1, #frames - 1, 2 do
            local p1 = frames[i].pos
            local p2 = frames[i + 1].pos
            local s1 = w2s(p1.x, p1.y, p1.z + 2.0)
            local s2 = w2s(p2.x, p2.y, p2.z + 2.0)
            if s1 and s2 then
                dl:add_line(s1.x, s1.y, s2.x, s2.y, 0.2, 0.8, 1.0, 0.7, 1.5)
            end
        end
    end

    -- 2. DIBUJAR CHECKPOINTS
    if CFG.show_checkpoints and #checkpoints > 0 then
        for _, cp in ipairs(checkpoints) do
            local sp = w2s(cp.pos.x, cp.pos.y, cp.pos.z + 3.0)
            if sp then
                dl:add_circle(sp.x, sp.y, 5.0, 1.0, 0.4, 0.8, 0.8, 16, 1.5)
            end
        end
    end

    -- 3. MARCADOR EN VIVO DE REPRODUCCION
    if current_state == STATE_PLAYING and frames[current_frame] then
        local cur_p = frames[current_frame].pos
        local sp = w2s(cur_p.x, cur_p.y, cur_p.z + 5.0)
        if sp then
            dl:add_circle_filled(sp.x, sp.y, 7.0, 0.0, 1.0, 1.0, 0.9, 16)
        end
    end

    -- 4. CAJITA DE ESTADO (TOP RIGHT)
    if CFG.show_status then
        local sw, sh = 1920, 1080
        pcall(function()
            local w_s, h_s = EngineClient.GetScreenSize()
            if w_s and w_s > 0 then sw, sh = w_s, h_s end
        end)

        local status_str = "IDLE"
        local status_col = { 0.5, 0.5, 0.5 }

        if current_state == STATE_RECORDING then
            status_str = string.format("RECORDING [%d]", #frames)
            status_col = { 1.0, 0.2, 0.2 }
        elseif current_state == STATE_PLAYING then
            if manual_override then
                status_str = "MANUAL OVERRIDE (HOLD 'R')"
                status_col = { 1.0, 0.6, 0.1 }
            else
                status_str = string.format("PLAYING [%d / %d]", current_frame, #frames)
                status_col = { 0.2, 1.0, 0.3 }
            end
        end

        local title = "Movement Recorder"
        local line2 = status_str
        local line3 = "F5: Rec | F6: Play | F7: Load | F8: Save"

        local bw = 240
        local bh = 54
        local bx = sw - bw - 20
        local by = 20

        dl:add_rect_filled(bx, by, bx + bw, by + bh, 0.05, 0.05, 0.08, 0.85, 6)
        dl:add_rect(bx, by, bx + bw, by + bh, 0.2, 0.2, 0.25, 0.8, 6)
        dl:add_text(bx + 10, by + 6, 0.9, 0.9, 0.9, 1.0, title)
        dl:add_text(bx + 10, by + 22, status_col[1], status_col[2], status_col[3], 1.0, line2)
        dl:add_text(bx + 10, by + 37, 0.5, 0.5, 0.5, 1.0, line3)
    end
end

function on_unload()
    current_state   = STATE_IDLE
    manual_override = false
    frames          = {}
    checkpoints     = {}
    client.print("[Recorder] Descargado.")
end

client.print("[Recorder] Cargado — F5: Rec | F6: Play | F7: Load | F8: Save | R: Resume")
