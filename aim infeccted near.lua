local ffi = require("ffi")
ffi.cdef[[ short GetAsyncKeyState(int vKey); ]]

local VK_MOUSE5 = 0x06

local config = {
    enabled       = true,
    fov           = 180.0,
    smooth        = 1.0,
    max_distance  = 8192.0,
    target_head   = true,
    silent_aim    = false,
    vischeck      = false,
    ignore_incap  = true,
}

local locked = nil

local function key_down(vk)
    return bit.band(ffi.C.GetAsyncKeyState(vk), 0x8000) ~= 0
end

local function normalize(a)
    while a > 180 do a = a - 360 end
    while a < -180 do a = a + 360 end
    return a
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function vx(v) return (v and (v.x or v[1])) or 0 end
local function vy(v) return (v and (v.y or v[2])) or 0 end
local function vz(v) return (v and (v.z or v[3])) or 0 end

local function dist(a, b)
    local dx = vx(a) - vx(b)
    local dy = vy(a) - vy(b)
    local dz = vz(a) - vz(b)
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function calc_angle(src, dst)
    local dx = vx(dst) - vx(src)
    local dy = vy(dst) - vy(src)
    local dz = vz(dst) - vz(src)
    local hyp = math.sqrt(dx*dx + dy*dy)
    if hyp < 0.001 then hyp = 0.001 end
    return {
        x = math.deg(math.atan2(-dz, hyp)),
        y = math.deg(math.atan2(dy, dx)),
        z = 0
    }
end

local function fov_to(view, aim)
    local dx = normalize(aim.x - vx(view))
    local dy = normalize(aim.y - vy(view))
    return math.sqrt(dx*dx + dy*dy)
end

local function smooth_angles(cur, target, smooth)
    if not smooth or smooth <= 1.0 then return target end
    local f = 1.0 / smooth
    return {
        x = vx(cur) + normalize(target.x - vx(cur)) * f,
        y = vy(cur) + normalize(target.y - vy(cur)) * f,
        z = 0
    }
end

local function get_local()
    local ok, p = pcall(EntityCache.GetLocal)
    if ok and p then return p end
    return nil
end

local function get_eye(p)
    local ok, eye = pcall(function() return p:EyePosition() end)
    if ok and eye then return eye end
    local ok2, o = pcall(function() return p:get_origin() end)
    if ok2 and o then
        return { x = vx(o), y = vy(o), z = vz(o) + 62.0 }
    end
    return nil
end

local function get_origin(p)
    local ok, o = pcall(function() return p:get_origin() end)
    if ok and o then return o end
    return nil
end

local function is_alive(p)
    local ok, a = pcall(function() return p:is_alive() end)
    if ok and a == false then return false end
    local ok2, hp = pcall(function() return p:GetHealth() end)
    if ok2 and hp and hp <= 0 then return false end
    return true
end

local function is_incap(p)
    local ok, v = pcall(function() return p:is_incapacitated() end)
    return ok and v == true
end

local function get_team(p)
    local ok, t = pcall(function() return p:get_team() end)
    if ok and t then return t end
    return 0
end

local function is_dormant_ent(ent)
    local ok, d = pcall(function()
        if ent.is_dormant then return ent:is_dormant() end
        return false
    end)
    return ok and d == true
end

local function set_angles(cmd, ang)
    cmd:set_viewangles(ang)
    if not config.silent_aim then
        pcall(function()
            if EngineClient.SetViewAngles then
                EngineClient.SetViewAngles(ang)
            elseif EngineClient.SetLocalViewAngles then
                EngineClient.SetLocalViewAngles(ang)
            end
        end)
    end
end

local function get_aim_pos(p)
    if config.target_head then
        local eye = get_eye(p)
        if eye then return eye end
    end
    local o = get_origin(p)
    if o then
        return { x = vx(o), y = vy(o), z = vz(o) + 40.0 }
    end
    return nil
end

local function get_best_target(lp)
    local eye = get_eye(lp)
    if not eye then return nil end

    local view = { x = 0, y = 0, z = 0 }
    pcall(function()
        local ea = lp:get_eye_angles()
        if ea then view = ea end
    end)

    local local_idx = EngineClient.GetLocalPlayer() or 0
    local max_ents = ClientEntityList.GetHighestEntityIndex() or 64

    local best = nil
    local best_fov = config.fov

    for i = 1, max_ents do
        if i == local_idx then goto continue end

        local ent = ClientEntityList.GetClientEntity(i)
        if not ent then goto continue end

        local ok_valid = true
        pcall(function()
            if ent.is_valid then ok_valid = ent:is_valid() end
        end)
        if not ok_valid then goto continue end

        if config.vischeck and is_dormant_ent(ent) then goto continue end

        local p = nil
        pcall(function() p = ent:as("CTerrorPlayer") end)
        if not p then goto continue end

        if get_team(p) ~= 2 then goto continue end
        if not is_alive(p) then goto continue end
        if config.ignore_incap and is_incap(p) then goto continue end

        local aim_pos = get_aim_pos(p)
        if not aim_pos then goto continue end

        local origin = get_origin(p)
        if not origin then goto continue end
        if dist(eye, origin) > config.max_distance then goto continue end

        local ang = calc_angle(eye, aim_pos)
        local f = fov_to(view, ang)
        if f < best_fov then
            best_fov = f
            best = { player = p, pos = aim_pos }
        end

        ::continue::
    end

    return best
end

function on_create_move(cmd, local_player)
    if not cmd then return end

    if not config.enabled then
        locked = nil
        return
    end

    if not key_down(VK_MOUSE5) then
        locked = nil
        return
    end

    if not EngineClient.IsInGame() then
        locked = nil
        return
    end

    local lp = local_player or get_local()
    if not lp then
        locked = nil
        return
    end

    if get_team(lp) ~= 3 then
        locked = nil
        return
    end

    local eye = get_eye(lp)
    if not eye then return end

    if locked then
        local ok = true
        if not is_alive(locked.player) then ok = false end
        if ok and get_team(locked.player) ~= 2 then ok = false end
        if ok and config.ignore_incap and is_incap(locked.player) then ok = false end
        if ok then
            local o = get_origin(locked.player)
            if not o or dist(eye, o) > config.max_distance then ok = false end
        end
        if not ok then locked = nil end
    end

    if not locked then
        locked = get_best_target(lp)
    end

    if locked then
        local aim_pos = get_aim_pos(locked.player) or locked.pos
        if aim_pos then
            local ang = calc_angle(eye, aim_pos)
            local current = cmd:get_viewangles()
            local final = ang
            if config.smooth > 1.0 then
                final = smooth_angles(current, ang, config.smooth)
            end
            final.x = clamp(normalize(final.x), -89.0, 89.0)
            final.y = normalize(final.y)
            final.z = 0
            set_angles(cmd, final)
        end
    end
end

local function draw_checkbox(label, field)
    local v = config[field] and true or false
    local newv = imgui.Checkbox(label, v)
    if newv ~= nil then
        config[field] = newv
    end
end

local function draw_slider_float(label, field, minv, maxv)
    local v = config[field] or 0
    local newv, changed = imgui.SliderFloat(label, v, minv, maxv)
    if changed then
        config[field] = newv
    end
end

pcall(function()
    menu.add_main_tab("AI", "Aim Infected", function()
        imgui.TextColored(1.0, 0.4, 0.4, 1.0, "Aim Infected")
        imgui.TextColored(0.5, 0.5, 0.5, 1.0, "Key: MOUSE5 hold")
        imgui.Separator()

        draw_checkbox("Enable", "enabled")
        draw_slider_float("FOV", "fov", 1.0, 180.0)
        draw_slider_float("Smooth (1=snap)", "smooth", 1.0, 20.0)
        draw_slider_float("Max distance", "max_distance", 200.0, 8192.0)

        imgui.Spacing()
        imgui.Separator()
        imgui.Text("Filters")
        draw_checkbox("Target head", "target_head")
        draw_checkbox("Silent aim", "silent_aim")
        draw_checkbox("Vischeck (dormant)", "vischeck")
        draw_checkbox("Ignore incapacitated", "ignore_incap")
    end)
end)

function on_unload()
    locked = nil
end
