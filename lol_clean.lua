
-- ============================================================
-- browser.lua — WebView2 browser overlay for L4D2
-- Revised version
-- Requires:
--   C:\Echidna-L4d2\browser.dll
--   C:\Echidna-L4d2\WebView2Loader.dll
-- ============================================================

local ffi = require("ffi")

ffi.cdef[[
    int  SetDllDirectoryA(const char* p);

    bool init_browser(void* dev, const char* url, int w, int h);
    bool browser_is_frame_ready(void);
    void browser_update_frame(void);
    void* browser_get_texture(void);

    void browser_navigate(const char* url);
    void browser_back(void);
    void browser_forward(void);
    void browser_reload(void);
    void browser_capture_now(void);

    bool browser_is_loading(void);
    const char* browser_get_url(void);

    void browser_send_mouse(int x, int y, int btn);
    void browser_send_scroll(int delta);
    void browser_send_char(unsigned int cp);
    void browser_send_key(int vk, bool down);

    void shutdown_browser(void);
]]

-- ============================================================
-- CONFIGURATION
-- ============================================================

local BASE = "C:\\Echidna-L4d2\\"

local BW, BH = 1280, 720
local WW, WH = 1320, 800

local START_URL = "https://www.google.com"
local TOOLBAR_H = 34

local BASE_FPS = 15
local ACTIVE_FPS = 30
local INPUT_DECAY = 2.0

local HISTORY_MAX = 20

-- ============================================================
-- DLL LOADING
-- ============================================================

ffi.C.SetDllDirectoryA(BASE)

if not ffi.abi("32bit") then
    error("[browser] This DLL requires a 32-bit game.")
end

local load_ok, br = pcall(ffi.load, BASE .. "browser.dll")

if not load_ok then
    error("[browser] DLL loading failed: " .. tostring(br))
end

-- ============================================================
-- STATE
-- ============================================================

local inited = false
local init_failed = false

local last_tex = nil
local texture_ready = false
local has_frame = false

local last_frame = 0
local last_input = 0

local url_input = START_URL
local focus = "none"

local url_history = {}

local prev_ctrl = false
local prev_shift = false

-- ============================================================
-- VIRTUAL KEYS
-- ============================================================

local VK = {
    BACK = 8,
    TAB = 9,
    RETURN = 13,
    SHIFT = 16,
    CTRL = 17,
    ESC = 27,

    LEFT = 37,
    UP = 38,
    RIGHT = 39,
    DOWN = 40,

    DELETE = 46,

    A = 65,
    C = 67,
    V = 86,
    X = 88,
    Z = 90
}

-- ============================================================
-- COLORS
-- ============================================================

local function IC(r, g, b, a)
    a = a or 255
    return {r / 255, g / 255, b / 255, a / 255}
end

local CBAR  = IC(28, 28, 36, 245)
local CLOAD = IC(80, 160, 255)
local CTXD  = IC(130, 130, 148)
local CBDR  = IC(55, 55, 75)
local CBKG  = IC(8, 8, 14)

-- ============================================================
-- HELPERS
-- ============================================================

local function touch_input()
    last_input = client.get_time()
end

local function get_frame_interval(now)
    if (now - last_input) < INPUT_DECAY then
        return 1 / ACTIVE_FPS
    end

    return 1 / BASE_FPS
end

local function normalize_url(s)
    s = s:match("^%s*(.-)%s*$")

    if s == "" then
        return s
    end

    if not s:match("^https?://") and not s:match("^file://") then
        if s:find(" ") or not s:find("%.") then
            return "https://www.google.com/search?q=" ..
                s:gsub(" ", "+")
        end

        return "https://" .. s
    end

    return s
end

local function history_push(url)
    if not url or url == "" or url == "about:blank" then
        return
    end

    for i = #url_history, 1, -1 do
        if url_history[i] == url then
            table.remove(url_history, i)
        end
    end

    table.insert(url_history, 1, url)

    if #url_history > HISTORY_MAX then
        table.remove(url_history)
    end
end

local function do_navigate(url)
    local nav = normalize_url(url)

    if nav == "" then
        return
    end

    br.browser_navigate(nav)
    br.browser_capture_now()

    history_push(nav)

    focus = "page"
    touch_input()
end

-- ============================================================
-- TEXTURE INITIALIZATION
-- ============================================================

local function initialize_texture()
    if texture_ready then
        return true
    end

    local raw = br.browser_get_texture()

    if raw == nil then
        print("[browser] Texture pointer is NULL.")
        return false
    end

    -- IMPORTANT:
    -- The D3D9 texture pointer remains the same during this session.
    -- Do not call tex_from_ptr again for every frame.

    local ok, tex = pcall(client.tex_from_ptr, raw)

    if not ok or tex == nil then
        print("[browser] tex_from_ptr failed: " .. tostring(tex))
        return false
    end

    last_tex = tex
    texture_ready = true

    print("[browser] Texture wrapper initialized.")

    return true
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

local function start()
    if inited or init_failed then
        return
    end

    local dev = client.get_d3d9_device()

    if not dev then
        return
    end

    print("[browser] Initializing WebView2...")

    local ok, result = pcall(
        br.init_browser,
        dev,
        START_URL,
        BW,
        BH
    )

    if not ok or not result then
        init_failed = true
        print("[browser] Initialization failed.")
        print("[browser] Not retrying to avoid unsafe DLL reinitialization.")
        return
    end

    inited = true

    print("[browser] WebView2 initialized.")

    initialize_texture()
end

-- ============================================================
-- FRAME UPDATE
-- ============================================================

local function update_frame(now)
    if not texture_ready then
        initialize_texture()
    end

    if not texture_ready then
        return
    end

    if (now - last_frame) < get_frame_interval(now) then
        return
    end

    last_frame = now

    if not br.browser_is_frame_ready() then
        return
    end

    br.browser_update_frame()

    has_frame = true
end

-- ============================================================
-- LOADING BAR
-- ============================================================

local function draw_loading_bar(dl, x, y, w, t)
    local pos = (t % 1.5) / 1.5

    local bw = w * 0.35
    local bx = x + (w + bw) * pos - bw

    bx = math.max(x, math.min(bx, x + w - 1))

    local ex = math.min(bx + bw, x + w)

    dl:add_rect_filled(
        bx, y,
        ex, y + 2,
        CLOAD[1], CLOAD[2], CLOAD[3], CLOAD[4]
    )
end

-- ============================================================
-- TOOLBAR
-- ============================================================

local function draw_toolbar(dl, wx, wy, ww, fh, now)

    dl:add_rect_filled(
        wx, wy + fh,
        wx + ww, wy + fh + TOOLBAR_H,
        CBAR[1], CBAR[2], CBAR[3], CBAR[4]
    )

    local bar_y = wy + fh + 6
    local cx = wx + 8

    local function tbtn(label, bw, fn)
        imgui.SetCursorScreenPos(cx, bar_y)

        if imgui.Button(label, bw, 22) then
            fn()
            touch_input()
        end

        cx = cx + bw + 4
    end

    tbtn("<", 22, function()
        br.browser_back()
        br.browser_capture_now()
    end)

    tbtn(">", 22, function()
        br.browser_forward()
        br.browser_capture_now()
    end)

    tbtn("R", 22, function()
        br.browser_reload()
        br.browser_capture_now()
    end)

    local url_w = ww - (cx - wx) - 16

    imgui.SetCursorScreenPos(cx, bar_y)
    imgui.SetNextItemWidth(url_w)

    local new_url = imgui.InputText("##url", url_input)

    if new_url ~= nil then
        url_input = new_url
        focus = "urlbar"
        touch_input()
    end

    if focus == "urlbar" and imgui.IsItemFocused() then
        if imgui.IsKeyPressed(VK.RETURN) then
            do_navigate(url_input)
        end
    end

    if imgui.IsItemClicked() then
        focus = "urlbar"
        touch_input()
    end

    if focus ~= "urlbar" then
        local ptr = br.browser_get_url()

        if ptr ~= nil then
            local ok, live = pcall(ffi.string, ptr)

            if ok and live ~= "" then
                url_input = live
            end
        end
    end

    local bottom_y = wy + fh + TOOLBAR_H

    if br.browser_is_loading() then
        draw_loading_bar(dl, wx, bottom_y - 2, ww, now)
    else
        dl:add_rect_filled(
            wx, bottom_y - 1,
            wx + ww, bottom_y,
            CBDR[1], CBDR[2], CBDR[3], CBDR[4]
        )
    end
end

-- ============================================================
-- VIEWPORT
-- ============================================================

local function draw_viewport(dl, vx, vy, vw, vh)

    local scale = math.min(vw / BW, vh / BH)

    local dw = math.floor(BW * scale)
    local dh = math.floor(BH * scale)

    local img_x = vx + math.floor((vw - dw) * 0.5)
    local img_y = vy + math.floor((vh - dh) * 0.5)

    dl:add_rect_filled(
        vx, vy,
        vx + vw, vy + vh,
        CBKG[1], CBKG[2], CBKG[3], CBKG[4]
    )

    if texture_ready and has_frame and last_tex ~= nil then

        dl:add_image(
            last_tex,
            img_x,
            img_y,
            img_x + dw,
            img_y + dh
        )

    else
        imgui.SetCursorScreenPos(
            vx + vw * 0.5 - 60,
            vy + vh * 0.5 - 7
        )

        imgui.TextDisabled(
            br.browser_is_loading()
            and "Loading..."
            or "Waiting for WebView2..."
        )
    end

    return img_x, img_y, dw, dh, scale
end

-- ============================================================
-- INPUT HANDLING
-- ============================================================

local function handle_input(img_x, img_y, dw, dh, scale)

    imgui.SetCursorScreenPos(img_x, img_y)
    imgui.InvisibleButton("##viewport", dw, dh)

    if imgui.IsItemHovered() then

        local mx, my = imgui.GetMousePos()

        local bx = math.floor((mx - img_x) / scale)
        local by = math.floor((my - img_y) / scale)

        br.browser_send_mouse(bx, by, 0)

        if imgui.IsMouseClicked(0) then
            br.browser_send_mouse(bx, by, 1)
            br.browser_send_mouse(bx, by, 2)

            focus = "page"

            br.browser_capture_now()
            touch_input()
        end

        if imgui.IsMouseClicked(1) then
            br.browser_send_mouse(bx, by, 3)
            br.browser_send_mouse(bx, by, 4)

            touch_input()
        end

        local wheel = imgui.GetMouseWheel and imgui.GetMouseWheel() or 0

        if wheel ~= 0 then
            br.browser_send_scroll(wheel > 0 and 3 or -3)
            br.browser_capture_now()
            touch_input()
        end
    end

    if focus ~= "page" then
        return
    end

    local ctrl = imgui.IsKeyDown(VK.CTRL)
    local shift = imgui.IsKeyDown(VK.SHIFT)

    if ctrl ~= prev_ctrl then
        br.browser_send_key(VK.CTRL, ctrl)
        prev_ctrl = ctrl
    end

    if shift ~= prev_shift then
        br.browser_send_key(VK.SHIFT, shift)
        prev_shift = shift
    end

    -- Ctrl combinations

    if ctrl then

        local function ctrl_key(vk)
            if imgui.IsKeyPressed(vk) then
                br.browser_send_key(vk, true)
                br.browser_send_key(vk, false)

                br.browser_capture_now()
                touch_input()
            end
        end

        ctrl_key(VK.A)
        ctrl_key(VK.C)
        ctrl_key(VK.V)
        ctrl_key(VK.X)
        ctrl_key(VK.Z)

        return
    end

    -- Printable characters

    local io_chars =
        imgui.GetInputCharacters and imgui.GetInputCharacters()

    if io_chars and #io_chars > 0 then
        for i = 1, #io_chars do
            br.browser_send_char(io_chars:byte(i))
        end

        br.browser_capture_now()
        touch_input()
    end

    -- Special keys

    local function fwd(vk)
        if imgui.IsKeyPressed(vk) then
            br.browser_send_key(vk, true)
            br.browser_send_key(vk, false)

            br.browser_capture_now()
            touch_input()
        end
    end

    fwd(VK.BACK)
    fwd(VK.RETURN)
    fwd(VK.TAB)
    fwd(VK.ESC)

    fwd(VK.LEFT)
    fwd(VK.RIGHT)
    fwd(VK.UP)
    fwd(VK.DOWN)

    fwd(VK.DELETE)
end

-- ============================================================
-- MAIN RENDER
-- ============================================================

function on_end_scene()

    if not client.is_menu_open() then
        return
    end

    if not inited then
        start()
        return
    end

    local now = client.get_time()

    update_frame(now)

    imgui.SetNextWindowSize(WW, WH, 4)

    if not imgui.Begin("Felix-Fox", nil, 0) then
        imgui.End()
        return
    end

    local dl = imgui.get_window_draw_list()

    local wx, wy = imgui.GetWindowPos()
    local ww, wh = imgui.GetWindowSize()

    local fh = imgui.GetFrameHeight()

    draw_toolbar(dl, wx, wy, ww, fh, now)

    local vx = wx
    local vy = wy + fh + TOOLBAR_H

    local vw = ww
    local vh = wh - fh - TOOLBAR_H

    local img_x, img_y, dw, dh, scale =
        draw_viewport(dl, vx, vy, vw, vh)

    handle_input(img_x, img_y, dw, dh, scale)

    imgui.End()
end

-- ============================================================
-- UNLOAD
-- ============================================================

function on_unload()

    if inited then

        br.shutdown_browser()

        inited = false
        last_tex = nil

        texture_ready = false
        has_frame = false

        print("[browser] Shutdown complete.")
    end
end

