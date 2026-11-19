-- @author: ported from original
-- @created: tracer directo
-- Echidna Script
-- Bullet tracer sin menú, sin icono, sin efecto.
-- Tracer ON, estilo Beam, fade Hold + Drop, color lavanda.

local cfg = {
    tracer_duration  = 0.8,
    tracer_thickness = 1.5,
    tracer_r         = 0.71,   -- lavanda #B57EDC
    tracer_g         = 0.49,
    tracer_b         = 0.86,
    tracer_a         = 1.0,
    fade_style       = 2,      -- 2 = Hold + Drop
    max_impacts      = 64,
}

local impacts = {}

local function get_eye_pos(ent)
    if not (ent and ent:is_valid()) then return nil end
    local p = ent:as("CTerrorPlayer") or ent
    return (p.EyePosition    and p:EyePosition())
        or (p.get_abs_origin and p:get_abs_origin())
        or (p.GetAbsOrigin   and p:GetAbsOrigin())
end

local function compute_fade(elapsed, duration)
    local t = math.max(0, math.min(1, 1 - elapsed / duration))
    if cfg.fade_style == 0 then return t * t end
    if cfg.fade_style == 1 then return t      end
    return t > 0.3 and 1.0 or (t / 0.3)
end

local function draw_tracer(dl, ox, oy, dx, dy, alpha)
    local r, g, b = cfg.tracer_r, cfg.tracer_g, cfg.tracer_b
    local a       = alpha * cfg.tracer_a
    local th      = cfg.tracer_thickness

    dl:add_line(ox, oy, dx, dy, r, g, b, a * 0.15, th * 6)
    dl:add_line(ox, oy, dx, dy, r, g, b, a * 0.40, th * 3)
    dl:add_line(ox, oy, dx, dy, r, g, b, a,         th)
end

local bullet_impact_id = events.add_listener("bullet_impact", function(ev)
    local local_idx = EngineClient.GetLocalPlayer()
    if EngineClient.GetPlayerForUserID(ev:GetInt("userid")) ~= local_idx then return end

    if #impacts >= cfg.max_impacts then table.remove(impacts, 1) end

    local local_ent = ClientEntityList.GetClientEntity(local_idx)
    table.insert(impacts, {
        pos    = { x = ev:GetFloat("x"), y = ev:GetFloat("y"), z = ev:GetFloat("z") },
        origin = get_eye_pos(local_ent),
        time   = os.clock(),
    })
end)

function on_end_scene()
    if not EngineClient.IsInGame() then return end
    if #impacts == 0 then return end

    local now    = os.clock()
    local vw, vh = imgui.GetDisplaySize()
    local sw, sh = EngineClient.GetScreenSize()
    local sx, sy = vw/sw, vh/sh
    local dl     = imgui.get_foreground_draw_list()

    for i = #impacts, 1, -1 do
        local impact  = impacts[i]
        local elapsed = now - impact.time

        if elapsed > cfg.tracer_duration then
            table.remove(impacts, i)
        else
            local ret, sp = DebugOverlay.ScreenPosition(impact.pos)
            if ret == 0 then
                local dx, dy = sp.x*sx, sp.y*sy
                if impact.origin then
                    local ret2, sp2 = DebugOverlay.ScreenPosition(impact.origin)
                    if ret2 == 0 then
                        draw_tracer(dl, sp2.x*sx, sp2.y*sy, dx, dy,
                            compute_fade(elapsed, cfg.tracer_duration))
                    end
                end
            end
        end
    end
end

function on_unload()
    if bullet_impact_id then
        events.remove_listener("bullet_impact", bullet_impact_id)
    end
end
