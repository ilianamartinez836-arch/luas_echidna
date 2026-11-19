-- @author: ported from Aimware
-- @created: snow directo
-- Echidna Script
-- Snow sin menú. Config fija: 200 partículas, blancas, velocidad base.

local cfg = {
    count   = 200,
    snow_sz = 2.0,
    snow_r  = 1.0,
    snow_g  = 1.0,
    snow_b  = 1.0,
}

local particles = {}
local last_count = 0

local function create_particle(screenW, screenH)
    return {
        x = math.random(-screenW, screenW),
        y = math.random(-screenH, screenH),
        z = math.random(10, 120),
        speed = math.random(40, 120),
        drift = math.random(-20, 20),
    }
end

local function rebuild_particles(n, screenW, screenH)
    particles = {}
    for i = 1, n do
        particles[i] = create_particle(screenW, screenH)
    end
end

local function get_screen_size()
    local ok, w, h = pcall(EngineClient.GetScreenSize)
    if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then
        return w, h
    end
    ok, w, h = pcall(imgui.GetDisplaySize)
    if ok and type(w) == "number" and type(h) == "number" then
        return w, h
    end
    return 1360, 768
end

local function get_frame_time()
    local ok, ft = pcall(client.get_frametime)
    if ok and type(ft) == "number" and ft > 0 then return ft end
    return 1 / 60
end

local function get_real_time()
    local ok, t = pcall(client.get_time)
    if ok and type(t) == "number" then return t end
    return os.clock()
end

local function get_view_vectors()
    local ang = nil
    local ok, a = pcall(EngineClient.GetViewAngles)
    if ok and a then ang = a end
    if not ang then
        return { x = 0, y = 1, z = 0 }, { x = 1, y = 0, z = 0 }
    end
    local ok2, v = pcall(mathutil.angle_vectors_full, ang)
    if ok2 and type(v) == "table" and v.forward and v.right then
        return v.forward, v.right
    end
    local pitch = math.rad(ang.x or 0)
    local yaw   = math.rad(ang.y or 0)
    local cp, sp = math.cos(pitch), math.sin(pitch)
    local cy, sy = math.cos(yaw),   math.sin(yaw)
    local fwd   = { x = cp * cy, y = cp * sy, z = -sp }
    local right = { x = sy,      y = -cy,     z = 0   }
    return fwd, right
end

function on_end_scene()
    local dl = imgui.get_foreground_draw_list()
    if not dl then return end

    local screenW, screenH = get_screen_size()
    local cx, cy = screenW / 2, screenH / 2

    local max_particles = math.floor(cfg.count or 200)
    if max_particles < 0 then max_particles = 0 end

    if max_particles ~= last_count then
        rebuild_particles(max_particles, screenW, screenH)
        last_count = max_particles
    end
    if #particles == 0 and max_particles > 0 then
        rebuild_particles(max_particles, screenW, screenH)
    end

    local ft   = get_frame_time()
    local time = get_real_time()

    local forward, right = get_view_vectors()
    local wind = math.sin(time * 0.5) * 25

    for i = 1, #particles do
        local p = particles[i]

        local depth = p.z / 120
        local inv   = 1 / depth

        p.y = p.y + p.speed * ft * inv
        p.x = p.x + (p.drift + wind) * ft

        p.x = p.x - right.x   * 40 * ft * inv
        p.y = p.y - forward.y * 40 * ft * inv

        local sx = cx + p.x * inv
        local sy = cy + p.y * inv

        if sy > screenH or sx < 0 or sx > screenW then
            particles[i] = create_particle(screenW, screenH)
        else
            local alpha = (255 * (1 - depth)) / 255
            if alpha < 0 then alpha = 0 end

            local size = math.max(1, math.floor((0.8 * inv) * cfg.snow_sz))
            dl:add_circle_filled(math.floor(sx), math.floor(sy), size,
                cfg.snow_r, cfg.snow_g, cfg.snow_b, alpha, 8)
        end
    end
end

function on_unload()
    particles = {}
    last_count = 0
end

