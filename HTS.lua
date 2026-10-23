-- HTS.lua | based on Night.lua by whoise1337 (@whoise10) | if you take code, mark it!!!
-- Nonagon build. Menu is created on load, callbacks are registered once at top level.

-- printed first on purpose: if the script dies later during load, this line still shows up
local function out(text)
    text = tostring(text)
    if client.log then pcall(client.log, text) end
    -- also echo into the game console, where it is always visible
    if client.console_exec then pcall(client.console_exec, "echo " .. text) end
end

out("HTS.lua l🗲ve KO4")

-- ============================== UTIL ==============================

local floor, sin, cos, pi = math.floor, math.sin, math.cos, math.pi
local rad = math.rad
local min, max = math.min, math.max

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- math.atan2 does not exist in this build
local function atan2(y, x)
    if x > 0 then return math.atan(y / x) end
    if x < 0 then
        if y >= 0 then return math.atan(y / x) + pi end
        return math.atan(y / x) - pi
    end
    if y > 0 then return pi / 2 end
    if y < 0 then return -pi / 2 end
    return 0
end

-- Players -------------------------------------------------------------------

local function get_players()
    if entity.get_players then return entity.get_players() end
    if entity.get_all_players then return entity.get_all_players() end
    return {}
end

local function find_player(name)
    if name == nil or not entity.get_name then return nil end
    for _, idx in ipairs(get_players()) do
        local ok, n = pcall(entity.get_name, idx)
        if ok and n == name then return idx end
    end
end

-- Events may hand out a pawn entity index (or even a userid) instead of the
-- controller index that all player functions expect: map it back when possible.
local function ctrl_from_pawn(v)
    if v == nil or not entity.get_pawn_idx or not entity.get_all_players then return nil end
    local ok, list = pcall(entity.get_all_players)
    if not ok or type(list) ~= "table" then return nil end
    for _, ctrl in ipairs(list) do
        local ok2, pawn = pcall(entity.get_pawn_idx, ctrl)
        if ok2 and pawn == v then return ctrl end
    end
end

local function victim_index(v)
    if type(v) == "number" then return ctrl_from_pawn(v) or v end
    return find_player(v)
end

local function is_local(who)
    if who == nil then return false end
    local me = entity.get_local_player()
    if me ~= nil then
        if who == me then return true end
        if entity.get_pawn_idx then
            local ok, pawn = pcall(entity.get_pawn_idx, me)
            if ok and pawn == who then return true end
        end
    end
    if type(who) == "string" then
        local ok, name = pcall(client.get_local_player_name)
        return ok and name ~= nil and who == name
    end
    return false
end

local function player_origin(idx)
    if idx == nil then return nil end
    local x, y, z = entity.get_origin(idx)
    if not x then return nil end
    return x, y, z
end

-- entity.get_weapon_name returns a bare name ("ak47", "taser"), so the weapon_ prefix is stripped.
local function weapon_name(idx)
    if idx == nil then return nil end

    if entity.get_weapon_name then
        local ok, wpn = pcall(entity.get_weapon_name, idx)
        if ok and type(wpn) == "string" and wpn ~= "" then
            return (wpn:lower():gsub("^weapon_", ""))
        end
    end

    if not entity.get_weapon then return nil end
    local ok, wpn = pcall(entity.get_weapon, idx)
    if not ok then return nil end
    if type(wpn) == "string" then return (wpn:lower():gsub("^weapon_", "")) end
    if type(wpn) == "table" then
        local n = wpn.name or wpn[1]
        if type(n) == "string" then return (n:lower():gsub("^weapon_", "")) end
    end
end

local function holds_taser(idx)
    local wpn = weapon_name(idx)
    if not wpn then return nil end
    return wpn:find("taser", 1, true) ~= nil or wpn:find("zeus", 1, true) ~= nil
end

-- every knife skin is "knife_..."; the bare default one is just "knife"
local function holds_knife(idx)
    local wpn = weapon_name(idx)
    if not wpn then return nil end
    return wpn:find("knife", 1, true) ~= nil or wpn:find("bayonet", 1, true) ~= nil
end

-- The taser has a recharge: in_reload stays true until it is usable again.
-- clip1 is only used for the debug line, some builds keep it at 0 for the taser even when ready.
local function weapon_clip(idx)
    if idx == nil or not entity.get_weapon_clip then return nil end
    local ok, clip1 = pcall(entity.get_weapon_clip, idx)
    if ok then return clip1 end
end

local function zeus_ready(idx)
    if idx == nil or not entity.get_weapon_clip then return true end
    local ok, _, _, in_reload = pcall(entity.get_weapon_clip, idx)
    if not ok then return true end
    if in_reload == true or in_reload == 1 then return false end
    return true
end

-- Colors --------------------------------------------------------------------
-- ui.add_color_picker uses 0..1 floats, draw.* takes 0..255 ints.

local color_get = ui.get_color or ui.get_color_picker

local function col(name, dr, dg, db, da)
    dr, dg, db, da = dr or 1, dg or 1, db or 1, da or 1
    if not color_get then
        return floor(dr * 255), floor(dg * 255), floor(db * 255), floor(da * 255)
    end
    local ok, r, g, b, a = pcall(color_get, name)
    if not ok then
        return floor(dr * 255), floor(dg * 255), floor(db * 255), floor(da * 255)
    end
    if type(r) == "table" then
        r, g, b, a = r[1], r[2], r[3], r[4]
    end
    if type(r) ~= "number" then
        return floor(dr * 255), floor(dg * 255), floor(db * 255), floor(da * 255)
    end
    return floor(clamp(r, 0, 1) * 255),
           floor(clamp(g or 1, 0, 1) * 255),
           floor(clamp(b or 1, 0, 1) * 255),
           floor(clamp(a or 1, 0, 1) * 255)
end

-- Glow drawing --------------------------------------------------------------

-- One bad event name must not abort the whole script at load.
local register_event = callbacks.register
local function on(event, fn)
    local ok, err = pcall(register_event, event, fn)
    if not ok then
        out("[HTS] register failed: " .. tostring(event) .. ": " .. tostring(err))
    end
end

-- Menu state: not in the documented API, so probe the usual names once and log what matched.
local menu_state_fn, menu_state_src = nil, "none"
do
    local probes = {
        { ui,     "is_menu_open",   "ui.is_menu_open" },
        { client, "is_menu_open",   "client.is_menu_open" },
        { ui,     "menu_open",      "ui.menu_open" },
        { client, "menu_open",      "client.menu_open" },
        { ui,     "is_open",        "ui.is_open" },
        { ui,     "is_menu_active", "ui.is_menu_active" },
    }
    for _, p in ipairs(probes) do
        local ns = p[1]
        if ns and type(ns[p[2]]) == "function" then
            menu_state_fn, menu_state_src = ns[p[2]], p[3]
            break
        end
    end
end

local function menu_is_open()
    if not menu_state_fn then return false end
    local ok, value = pcall(menu_state_fn)
    return ok and value and true or false
end

-- Game's own front-end (main menu / loading): no map, or no local player yet.
local function game_menu_open()
    local map = client.get_map_data()
    if type(map) == "string" then
        local m = map:lower()
        if m == "" or m == "menu" or m:find("menu", 1, true) then
            return true
        end
    end
    return entity.get_local_player() == nil
end

local function glow_line(ax, ay, bx, by, r, g, b, a, layers)
    if layers and layers > 0 then
        for gi = layers, 1, -1 do
            local ga = floor(a * (1.0 - gi / layers) * 0.35)
            if ga > 2 then
                draw.line(ax - gi, ay,      bx - gi, by,      r, g, b, ga)
                draw.line(ax + gi, ay,      bx + gi, by,      r, g, b, ga)
                draw.line(ax,      ay - gi, bx,      by - gi, r, g, b, ga)
                draw.line(ax,      ay + gi, bx,      by + gi, r, g, b, ga)
            end
        end
    end
    draw.line(ax, ay, bx, by, r, g, b, a)
end

-- ============================== MENU ==============================

local GROUPS = {
    "HTS | Hitmarker",   -- removed, kept so its stale widgets get cleared
    "HTS | Velocity",
    "HTS | Tracer",
    "HTS | Damage",
    "HTS | Particles",
    "HTS | Nimb",
    "HTS | Rage helper",
    "HTS | Misc",
    "HTS | Watermark",
}

if callbacks.clear then
    pcall(callbacks.clear)
end

if ui.clear_group then
    for _, g in ipairs(GROUPS) do
        pcall(ui.clear_group, g)
    end
end

-- Velocity fonts: "Pixel" is the built-in 5x7 font, the rest are pre-baked
-- bitmaps of the fonts installed with Windows.
local FONT = {
    names = {
        "Pixel", "Arial", "Segoe UI", "Tahoma", "Verdana", "Calibri", "Consolas",
        "Impact", "Georgia", "Trebuchet MS", "Comic Sans MS", "Courier New",
        "Bahnschrift", "Arial Black",
    },
    cache = {},
}

-- Velocity indicator
ui.begin_group("HTS | Velocity", true)
ui.add_checkbox("Velocity indicator")
ui.add_checkbox("Velocity keybinds")
if ui.add_combo then
    ui.add_combo("Velocity font", FONT.names, 0)
end
ui.add_color_picker("Velocity color", 0.62, 0.32, 1.0, 1.0)
ui.end_group()

-- Tracer
ui.begin_group("HTS | Tracer", true)
ui.add_checkbox("Tracer enabled")
ui.add_checkbox("Tracer pulse")
ui.add_color_picker("Tracer color", 0.35, 0.65, 1.0, 1.0)
ui.add_slider_int("Tracer glow", 1, 10)
ui.add_slider_float("Tracer lifetime", 0.5, 6.0, 3.0)
ui.end_group()

-- Damage
ui.begin_group("HTS | Damage", true)
ui.add_checkbox("Damage indicator")
ui.add_color_picker("Damage color", 1.0, 0.4, 0.4, 1.0)
ui.add_slider_int("Damage drift", 20, 200)
ui.add_slider_float("Damage duration", 0.5, 4.0, 1.8)
ui.end_group()

-- Particles
ui.begin_group("HTS | Particles", false)
ui.add_checkbox("Souls enabled")
ui.add_color_picker("Souls color", 0.55, 0.85, 1.0, 1.0)
ui.add_slider_int("Souls size", 1, 8, 3)
ui.add_slider_float("Souls lifetime", 0.3, 3.0, 0.9)
ui.add_slider_int("Souls count", 10, 120, 60)
ui.add_checkbox("Cubes enabled")
ui.add_color_picker("Cubes color", 0.7, 0.5, 1.0, 1.0)
ui.add_slider_int("Cubes size", 1, 8, 3)
ui.add_slider_float("Cubes lifetime", 0.3, 3.0, 0.9)
ui.add_slider_int("Cubes glow", 1, 10, 3)
ui.add_slider_int("Cubes count", 6, 80, 40)
ui.add_checkbox("Sparks enabled")
ui.add_color_picker("Sparks color", 1.0, 0.75, 0.3, 1.0)
ui.add_slider_int("Sparks glow", 0, 8, 2)
ui.add_slider_int("Sparks count", 5, 80, 40)
ui.add_checkbox("???")
ui.end_group()

-- Nimb
ui.begin_group("HTS | Nimb", false)
ui.add_checkbox("Nimb enabled")
ui.add_checkbox("Nimb pulse")
ui.add_color_picker("Nimb color", 0.5, 0.8, 1.0, 1.0)
ui.add_slider_int("Nimb radius", 6, 48, 12)
ui.add_slider_int("Nimb height", 0, 60, 0)
ui.add_slider_int("Nimb glow", 0, 8, 3)
ui.add_slider_int("Nimb thickness", 1, 5, 2)
ui.end_group()

-- Rage helper
ui.begin_group("HTS | Rage helper", true)
ui.add_checkbox("Zeus bot")
ui.add_slider_int("Zeus range", 10, 200, 60)
ui.add_slider_int("Zeus hit chance", 1, 100, 60)
ui.add_checkbox("Knife bot")
ui.add_checkbox("Avoid backstab")
ui.add_slider_int("Backstab radius", 100, 800, 600)
ui.end_group()

-- Misc
ui.begin_group("HTS | Misc", false)
ui.add_checkbox("Kill message")
ui.add_checkbox("Chat spam")
ui.add_slider_float("Chat spam delay", 1.0, 30.0, 5.0)
ui.add_checkbox("No sound jump")
ui.end_group()

-- Watermark
ui.begin_group("HTS | Watermark", true)
ui.add_checkbox("Watermark enabled")
ui.add_combo("Watermark anchor", { "Camera", "Target", "Top left", "Top right", "Bottom left", "Bottom right" }, 0)
ui.add_checkbox("Watermark frame")
ui.add_checkbox("Watermark cog")
ui.add_color_picker("Watermark color", 0.62, 0.32, 1.0, 1.0)
ui.add_color_picker("Watermark color 2", 1.0, 1.0, 1.0, 1.0)
ui.add_slider_float("Watermark smooth", 1.0, 12.0, 6.0)
ui.add_slider_int("Watermark offset x", -100, 100, 0)
ui.add_slider_int("Watermark offset y", -100, 100, 0)
ui.add_slider_int("Watermark offset z", -40, 120, 20)
ui.end_group()

-- Defaults ------------------------------------------------------------------
-- Injected script is usable immediately; anything not listed here starts off.

local DEFAULT_ON = {
    "Watermark enabled", "Watermark frame", "Watermark cog",
    "Velocity indicator", "Velocity keybinds",
    "Tracer enabled", "Damage indicator",
    "Souls enabled", "Cubes enabled", "Sparks enabled", "Nimb enabled",
    "No sound jump", "Knife bot", "Avoid backstab",
}

local DEFAULT_INT = {
    { "Tracer glow", 4 },
    { "Damage drift", 60 },
    { "Souls size", 3 },
    { "Souls count", 60 },
    { "Cubes size", 3 },
    { "Cubes glow", 3 },
    { "Cubes count", 40 },
    { "Sparks glow", 2 },
    { "Sparks count", 40 },
    { "Nimb radius", 12 },
    { "Nimb glow", 3 },
    { "Nimb thickness", 2 },
    { "Zeus range", 60 },
    { "Zeus hit chance", 60 },
    { "Backstab radius", 600 },
}

if ui.set_bool then
    for _, name in ipairs(DEFAULT_ON) do
        pcall(ui.set_bool, name, true)
    end
else
    out("[HTS] ui.set_bool missing: defaults are off, tick the boxes manually")
end

if ui.set_int then
    for _, row in ipairs(DEFAULT_INT) do
        pcall(ui.set_int, row[1], row[2])
    end
end

-- ============================== STATE ==============================

local tracers    = {}
local damage     = {}

local last_origin = {}    -- [player index] = { x, y, z }
local last_hurt   = {}    -- [victim index] = { x, y, z }

local souls      = {}
local cubes      = {}
local sparks     = {}
local rockets    = {}

local shot_eye   = { x = 0, y = 0, z = 0, time = -100 }

local nimb_pos   = { x = nil, y = nil, z = nil }
local real_yaw   = 0
local view_pitch = 0
local view_yaw   = 0

-- watermark anchor smoothing + last ragebot evaluation
local mark_pos = { x = nil, y = nil, z = nil }
local rage       = {
    time = -100, target = nil, valid = false,
    damage = 0, hitbox = 0, hc = 0, required = 0,
    fov = 0, dist = 0, x = 0, y = 0, z = 0,
}

local zeus_holding = false
local zeus_log_time = -100
local knife_holding = false
local knife_heavy_holding = false
local knife_log_time = -100
local knife_stage = 0          -- 0 idle, 1 light slashes, 2 heavy slash, 3 cooldown
local knife_stage_tick = 0
local knife_aim = { on = false, pitch = 0, yaw = 0 }
local guard_aim = { on = false, yaw = 0 }
local spam_timer   = -100


-- Secret toggle: read defensively, the control name is deliberately odd.
local function secret_on()
    local ok, v = pcall(ui.get_bool, "???")
    return ok and v and true or false
end

-- FPS: no frametime in the API, so count frames against a millisecond clock.
local fps_state = { frames = 0, last = 0, value = 0 }

local function now_ms()
    if client.get_timestamp then
        local ok, v = pcall(client.get_timestamp)
        if ok and type(v) == "number" then return v end
    end
    if os and os.clock then return floor(os.clock() * 1000) end
    return floor(client.curtime() * 1000)
end

local function update_fps()
    local t = now_ms()
    if not t then return end
    local f = fps_state
    if f.last == 0 then
        f.last = t
        return
    end
    f.frames = f.frames + 1
    local dt = t - f.last
    if dt >= 500 then
        f.value = floor(f.frames * 1000 / dt)
        f.frames = 0
        f.last = t
    end
end

-- ============================== PARTICLES ==============================

local function spawn_souls(wx, wy, wz)
    local now  = client.curtime()
    local size = clamp(ui.get_int("Souls size"), 1, 8)
    local life = clamp(ui.get_float("Souls lifetime"), 0.3, 3.0)
    local count = clamp(ui.get_int("Souls count"), 10, 120)
    for _ = 1, count do
        local angle  = math.random() * pi * 2
        local spread = 0.18 + math.random() * 0.22
        souls[#souls + 1] = {
            wx = wx + (math.random() - 0.5) * 24,
            wy = wy + (math.random() - 0.5) * 24,
            wz = wz + math.random() * 8,
            vx = cos(angle) * spread,
            vy = sin(angle) * spread,
            vz = 0.25 + math.random() * 0.35,
            born = now,
            life = life * (0.5 + math.random() * 0.6),
            size = size * (1.2 + math.random() * 1.8),
        }
    end
end

local function spawn_cubes(wx, wy, wz)
    local now  = client.curtime()
    local size = clamp(ui.get_int("Cubes size"), 1, 8)
    local life = clamp(ui.get_float("Cubes lifetime"), 0.3, 3.0)
    local count = clamp(ui.get_int("Cubes count"), 6, 80)
    for _ = 1, count do
        local angle  = math.random() * pi * 2
        local spread = 0.20 + math.random() * 0.25
        cubes[#cubes + 1] = {
            wx = wx + (math.random() - 0.5) * 24,
            wy = wy + (math.random() - 0.5) * 24,
            wz = wz + math.random() * 8,
            vx = cos(angle) * spread,
            vy = sin(angle) * spread,
            vz = 0.20 + math.random() * 0.30,
            born = now,
            life = life * (0.5 + math.random() * 0.6),
            size = size * (0.5 + math.random() * 0.8),
            rx = math.random() * pi * 2,
            ry = math.random() * pi * 2,
            rz = math.random() * pi * 2,
            rxs = (math.random() - 0.5) * 4.0,
            rys = (math.random() - 0.5) * 4.0,
            rzs = (math.random() - 0.5) * 4.0,
        }
    end
end

local function spawn_sparks(wx, wy, wz)
    local now   = client.curtime()
    local count = clamp(ui.get_int("Sparks count"), 5, 80)
    local cr, cg, cb = col("Sparks color", 1.0, 0.75, 0.3, 1.0)
    for _ = 1, count do
        local angle = math.random() * pi * 2
        local hspd  = 60 + math.random() * 120
        sparks[#sparks + 1] = {
            x = wx + (math.random() - 0.5) * 10,
            y = wy + (math.random() - 0.5) * 10,
            z = wz + 10 + math.random() * 50,
            vx = cos(angle) * hspd,
            vy = sin(angle) * hspd,
            vz = 10 + math.random() * 60,
            born = now,
            life = 1.5,
            r = clamp(cr + math.random(-30, 30), 0, 255),
            g = clamp(cg + math.random(-30, 30), 0, 255),
            b = clamp(cb + math.random(-30, 30), 0, 255),
        }
    end
end

-- secret: launched skyward on a kill
local function spawn_rocket(x, y, z)
    local now = client.curtime()
    local count = 2 + math.random(0, 2)
    out(string.format("[HTS debug] rocket spawn x%d", count))
    for _ = 1, count do
        rockets[#rockets + 1] = {
            x = x + (math.random() - 0.5) * 26,
            y = y + (math.random() - 0.5) * 26,
            z = z + 30 + math.random() * 20,
            vx = (math.random() - 0.5) * 24,
            vy = (math.random() - 0.5) * 24,
            vz = 120 + math.random() * 100,
            size = 4.0 + math.random() * 2.5,
            phase = math.random() * pi * 2,
            born = now,
            life = 3.0 + math.random() * 0.8,
        }
    end
end

-- ============================== RENDER ==============================

-- Text metrics: the API has no measure_text, so width is estimated per glyph.
local CHAR_W = 6
local LINE_H = 12

local function fill_rect(x, y, w, h, r, g, b, a)
    if draw.rect_filled then
        draw.rect_filled(x, y, w, h, r, g, b, a)
        return
    end
    for i = 0, h - 1 do
        draw.line(x, y + i, x + w, y + i, r, g, b, a)
    end
end

local function draw_cog(cx, cy, radius, r, g, b, a)
    draw.circle(cx, cy, radius, r, g, b, a)
    for i = 0, 7 do
        local ang = i * (pi / 4)
        local ca, sa = cos(ang), sin(ang)
        draw.line(cx + ca * (radius - 1), cy + sa * (radius - 1),
                  cx + ca * (radius + 3), cy + sa * (radius + 3), r, g, b, a)
    end
    draw.circle_filled(cx, cy, 1, r, g, b, a)
end

local function hc_color(hc)
    if hc >= 70 then return 120, 255, 140 end
    if hc >= 40 then return 255, 220, 110 end
    return 255, 110, 110
end

-- Live ragebot snapshot (documented as safe from render). Falls back to the cached callback state.
local function rage_live()
    if ragebot and ragebot.get_target then
        local ok, ent, valid, damage, hitbox, hc, required, fov, distance = pcall(ragebot.get_target)
        if ok and valid then
            local pct = hc or 0
            if pct > 0 and pct <= 1 then pct = pct * 100 end
            return {
                target = ent, valid = true,
                damage = damage or 0, hitbox = hitbox or 0,
                hc = pct, required = required or 0,
                fov = fov or 0, dist = distance or 0,
                time = client.curtime(),
            }
        end
    end
    return rage
end

-- Camera / target anchor in world space. Corner anchors return nil and are placed on screen.
local function watermark_anchor()
    local mode = ui.get_combo("Watermark anchor") or 0
    local ox   = ui.get_int("Watermark offset x")
    local oy   = ui.get_int("Watermark offset y")
    local oz   = ui.get_int("Watermark offset z")

    if mode == 1 then
        local t = rage_live().target
        if not t then return nil end
        local tx, ty, tz = entity.get_origin(t)
        if not tx and entity.get_ent_origin then
            -- ragebot may hand out a pawn index instead of a controller index
            tx, ty, tz = entity.get_ent_origin(t)
        end
        if not tx then return nil end
        return tx + ox, ty + oy, tz + oz
    end

    if mode == 0 then
        local ex, ey, ez = client.get_eye_pos()
        if not ex then return nil end
        local p, y = rad(view_pitch), rad(view_yaw)
        local cp = cos(p)
        local fx, fy, fz = cp * cos(y), cp * sin(y), -sin(p)
        local rx, ry = -sin(y), cos(y)
        local dist = 40 + oz
        if dist < 10 then dist = 10 end
        return ex + fx * dist + rx * ox,
               ey + fy * dist + ry * ox,
               ez + fz * dist + oy
    end
end

local function render_watermark(now)
    if not ui.get_bool("Watermark enabled") then
        mark_pos.x = nil
        return
    end

    local sw, sh = client.screen_size()
    local mode   = ui.get_combo("Watermark anchor") or 0

    -- Camera anchor sits in the middle of the screen: don't draw over the game front-end or the menu.
    if mode == 0 and (game_menu_open() or menu_is_open()) then return end

    local text   = string.format("HTS lua / %d fps", fps_state.value)
    local cog    = ui.get_bool("Watermark cog")
    local text_w = #text * CHAR_W
    local box_w  = text_w + 12 + (cog and 18 or 0)
    local box_h  = LINE_H + 8

    local cx, cy
    if mode >= 2 then
        local pad = 10
        local bx, by
        if mode == 2 then       -- top left
            bx, by = pad, pad
        elseif mode == 3 then   -- top right
            bx, by = sw - pad - box_w, pad
        elseif mode == 4 then   -- bottom left
            bx, by = pad, sh - pad - box_h
        else                    -- bottom right
            bx, by = sw - pad - box_w, sh - pad - box_h
        end
        cx, cy = bx + box_w / 2, by + box_h / 2
    else
        local ax, ay, az = watermark_anchor()
        if not ax then return end

        local smooth = clamp(ui.get_float("Watermark smooth"), 1.0, 12.0)
        local k = clamp(1.0 / smooth, 0.05, 1.0)
        if mark_pos.x == nil then
            mark_pos.x, mark_pos.y, mark_pos.z = ax, ay, az
        else
            mark_pos.x = lerp(mark_pos.x, ax, k)
            mark_pos.y = lerp(mark_pos.y, ay, k)
            mark_pos.z = lerp(mark_pos.z, az, k)
        end

        local px, py, ok = client.world_to_screen(mark_pos.x, mark_pos.y, mark_pos.z)
        if not ok then return end
        cx, cy = px, py
    end

    local r1, g1, b1 = col("Watermark color", 0.62, 0.32, 1.0, 1.0)
    local r2, g2, b2 = col("Watermark color 2", 1.0, 1.0, 1.0, 1.0)
    local f  = sin(now * 2.0) * 0.5 + 0.5
    local cr = floor(lerp(r1, r2, f))
    local cg = floor(lerp(g1, g2, f))
    local cb = floor(lerp(b1, b2, f))

    local left = floor(cx - box_w / 2)
    local top  = floor(cy - box_h / 2)

    if ui.get_bool("Watermark frame") then
        fill_rect(left, top, box_w, box_h, 8, 10, 16, 200)
        draw.rect(left, top, box_w, box_h, cr, cg, cb, 230)
    end

    draw.text(left + 6, top + 4, text, cr, cg, cb, 245)

    if cog then
        draw_cog(left + 6 + text_w + 9, top + box_h / 2, 4, cr, cg, cb, 230)
    end

    -- Rage target readout under the plate, only when anchored to the model.
    local r = rage_live()
    if mode == 1 and r.valid and (now - r.time) <= 0.35 then
        local lines = {}
        local wpn = weapon_name(entity.get_local_player())
        if wpn then
            lines[#lines + 1] = { wpn:upper(), r1, g1, b1, 220 }
        end
        lines[#lines + 1] = {
            string.format("dmg %d | min %d", floor(r.damage), floor(r.required)),
            r1, g1, b1, 210,
        }
        local hr, hg, hb = hc_color(r.hc)
        lines[#lines + 1] = { string.format("hc %d%%", floor(r.hc)), hr, hg, hb, 235 }

        local y = top + box_h + 4
        for _, ln in ipairs(lines) do
            local x = floor(cx - (#ln[1] * CHAR_W) / 2)
            draw.text(x + 1, y + 1, ln[1], 0, 0, 0, 150)
            draw.text(x, y, ln[1], ln[2], ln[3], ln[4], ln[5])
            y = y + LINE_H
        end
    end
end

-- Velocity HUD ----------------------------------------------------------------
-- Like the reference: a big speed number with the keystroke row right under it.
-- No panel, no frame, no graph — just floating glyphs.

-- WASD keys -------------------------------------------------------------------
-- Read from the usercmd button mask; if that getter is not available, fall back
-- to projecting the local velocity on the view axes.

local IN_FORWARD   = 8
local IN_BACK      = 16
local IN_MOVELEFT  = 512
local IN_MOVERIGHT = 1024
local IN_JUMP      = 2
local IN_DUCK      = 4

local wasd = {
    w      = { down = false, level = 0 },
    a      = { down = false, level = 0 },
    s      = { down = false, level = 0 },
    d      = { down = false, level = 0 },
    jump   = { down = false, level = 0 },
    crouch = { down = false, level = 0 },
}
local wasd_last   = 0
local keys_vis    = 1
local wasd_probed = false

local function update_wasd(me)
    local w, a, s, d = false, false, false, false
    local jump, crouch = false, false

    local ok, mask = pcall(cmd.buttons)
    if ok and type(mask) == "number" then
        w = (mask & IN_FORWARD) ~= 0
        a = (mask & IN_MOVELEFT) ~= 0
        s = (mask & IN_BACK) ~= 0
        d = (mask & IN_MOVERIGHT) ~= 0
        jump   = (mask & IN_JUMP) ~= 0
        crouch = (mask & IN_DUCK) ~= 0
    elseif me then
        local okv, vx, vy = pcall(entity.get_velocity, me)
        if okv and type(vx) == "number" then
            if type(vy) ~= "number" then vy = 0 end
            if vx * vx + vy * vy > 3600 then
                local rad  = math.rad(view_yaw or 0)
                local fwd  = vx * math.cos(rad) + vy * math.sin(rad)
                local side = vx * math.sin(rad) - vy * math.cos(rad)
                if fwd > 25 then w = true elseif fwd < -25 then s = true end
                if side > 25 then d = true elseif side < -25 then a = true end
            end
        end
    end

    wasd.w.down, wasd.a.down, wasd.s.down, wasd.d.down = w, a, s, d
    wasd.jump.down, wasd.crouch.down = jump, crouch

    if not wasd_probed then
        wasd_probed = true
        local pok, pmask = pcall(cmd.buttons)
        out("[HTS debug] wasd probe: ok=" .. tostring(pok) .. " mask=" .. tostring(pmask))
    end
end

-- 5x7 pixel font for the speed number and the key row: letters are drawn scaled,
-- without boxes.
local GLYPHS = {
    W = { "10001", "10001", "10001", "10101", "10101", "11011", "10001" },
    A = { "01110", "10001", "10001", "11111", "10001", "10001", "10001" },
    S = { "01111", "10000", "10000", "01110", "00001", "00001", "11110" },
    D = { "11110", "10001", "10001", "10001", "10001", "10001", "11110" },
    J = { "00111", "00010", "00010", "00010", "00010", "10010", "01100" },
    C = { "01110", "10001", "10000", "10000", "10000", "10001", "01110" },
    ["0"] = { "01110", "10001", "10011", "10101", "11001", "10001", "01110" },
    ["1"] = { "00100", "01100", "00100", "00100", "00100", "00100", "01110" },
    ["2"] = { "01110", "10001", "00001", "00010", "00100", "01000", "11111" },
    ["3"] = { "11111", "00010", "00100", "00010", "00001", "10001", "01110" },
    ["4"] = { "00010", "00110", "01010", "10010", "11111", "00010", "00010" },
    ["5"] = { "11111", "10000", "11110", "00001", "00001", "10001", "01110" },
    ["6"] = { "00110", "01000", "10000", "11110", "10001", "10001", "01110" },
    ["7"] = { "11111", "00001", "00010", "00100", "01000", "01000", "01000" },
    ["8"] = { "01110", "10001", "10001", "01110", "10001", "10001", "01110" },
    ["9"] = { "01110", "10001", "10001", "01111", "00001", "00010", "01100" },
}

-- 3x2 key grid: jump and crouch to the left of W, movement under them.
local KEY_GRID = {
    { "J", "jump",   0, 0 },
    { "C", "crouch", 1, 0 },
    { "W", "w",      2, 0 },
    { "A", "a",      0, 1 },
    { "S", "s",      1, 1 },
    { "D", "d",      2, 1 },
}

local function draw_glyph(gx, gy, glyph, scale, r, g, b, a)
    for row = 1, 7 do
        local line = glyph[row]
        local col = 1
        while col <= 5 do
            if line:sub(col, col) == "1" then
                local start = col
                while col <= 5 and line:sub(col, col) == "1" do
                    col = col + 1
                end
                fill_rect(gx + (start - 1) * scale, gy + (row - 1) * scale,
                          (col - start) * scale, scale, r, g, b, a)
            else
                col = col + 1
            end
        end
    end
end

-- Centered run of glyphs (speed number).
local function draw_text_glyphs(cx, y, text, scale, gap, r, g, b, a)
    local n = #text
    local total = n * 5 * scale + (n - 1) * gap
    local x = floor(cx - total / 2)
    for i = 1, n do
        local glyph = GLYPHS[text:sub(i, i)]
        if glyph then
            draw_glyph(x, y, glyph, scale, r, g, b, a)
        end
        x = x + 5 * scale + gap
    end
end

-- Windows fonts ---------------------------------------------------------------
-- Glyphs are pre-baked from the installed Windows font at two sizes (key row and
-- speed number) as 1-bit rows, so drawing is just a few fill_rect calls.

FONT.data = {
    ["Arial"] = {
        keys = { bits = 5, em = 20, c = {
            ["J"] = { 10, 4, "03800038000380003800038000380003800038000380003800e3800e3800f78007f0003e000" },
            ["C"] = { 14, 4, "0fe001ff003c780703807038070000e0000e0000e000070100703c0703803c7801ff000fe00" },
            ["W"] = { 19, 4, "e0f0ee0f0ee1f0e71f0e71f9c73b9c73b9c3b99c3b1f83f1f83f1f81f0f81e0f01e0f01e0f0" },
            ["A"] = { 13, 4, "0f0000f0000f8001f8001f8001dc0039c0039c0038e007fe007ff00f0700e0700e0380e0380" },
            ["S"] = { 13, 4, "1fc003fe0078f007070070000780003f8000fe0001f0000700e03807078078f003fe001fc00" },
            ["D"] = { 14, 4, "7fc007ff0070f007038070380701c0701c0701c0701c070380703807038070f007ff007fc00" },
        } },
        num = { bits = 5, em = 30, c = {
            ["0"] = { 17, 6, "07f000ff801ffc03ffe03f7e07e3f07c3f07c1f07c1f07c1f07c1f07c1f07c1f07c1f07c1f07c3f07e3f03f7e03ffe01ffc00ff8007f00" },
            ["1"] = { 15, 6, "00f8001f8003f8007f801ff803ff803ff803df8031f8001f8001f8001f8001f8001f8001f8001f8001f8001f8001f8001f8001f8001f80" },
            ["2"] = { 17, 6, "07f001ffc03ffe07fff07e3f07c1f07c1f0001f0003f0003e0007e000fc001f8003f0007e000f8001f0003e0007fff07fff0ffff0ffff0" },
            ["3"] = { 17, 6, "07f001ff801ffc03ffe03e7e07e3e03c3e0003e0007c001f8003f8003fc0007e0003f0001f07c1f07e3f07f7f03ffe03ffe01ffc007f00" },
            ["4"] = { 17, 6, "007c000fc000fc001fc003fc003fc007fc00ffc00ffc01f7c03e7c03e7c07c7c0f87c0ffff8ffff8ffff8ffff8007c0007c0007c0007c0" },
            ["5"] = { 17, 6, "1fff01fff01fff01fff01f0003e0003e0003ff803ffc03ffe07fff07e3f03c1f0001f0001f07c1f07e1f07f3f03ffe03ffe01ffc007f00" },
            ["6"] = { 17, 6, "03f800ffc01ffe03ffe03f3f07e1f07e0007c0007df807ffc07ffe07fff07f3f07e1f07e1f07e1f07e1f03f3f03fff01ffe00ffc007f00" },
            ["7"] = { 17, 6, "7fff07fff07fff07fff0003e0007c000fc000f8001f0001f0003e0003e0007e0007c0007c000fc000f8000f8000f8000f8001f8001f800" },
            ["8"] = { 17, 6, "07f001ffc03ffc03e7e07c3e07c3e07c3e07c3e03e7e01ffc00ff801ffc03e7e07e3f07c1f07c1f07c1f07e3f07f7e03ffe01ffc007f00" },
            ["9"] = { 17, 6, "0fe001ff803ffc07ffe07e7e07c3f0fc3f0fc3f07c3f07e7f07fff03fff01fff00fdf0003f0003f07c3e07e7e07ffe03ffc01ff800fe00" },
        } },
    },
    ["Segoe UI"] = {
        keys = { bits = 5, em = 20, c = {
            ["J"] = { 6, 9, "1c0001c0001c0001c0001c0001c0001c0001c0001c0001c0001c00018000f8000f0000" },
            ["C"] = { 11, 9, "0fe001fe00380007000070000e0000e0000e0000e00006000070000380003fe000fe00" },
            ["W"] = { 19, 9, "e0e0ee0e0ee0f0e71f1c71f1c71b9c33b983bbb83b9b83f1f81f1f01f1f01e0f00e0e0" },
            ["A"] = { 13, 9, "070000f8000f8000d8001dc001dc0018c0038e0038e007ff007ff0060700e0380e0380" },
            ["S"] = { 11, 9, "1fc007fc00700006000070000780003e0000f80003c0001c0000c0061c007fc007f000" },
            ["D"] = { 14, 9, "7fc007ff00707007038070380701c0701c0701c0701807038070380707007fe007f800" },
        } },
        num = { bits = 5, em = 30, c = {
            ["0"] = { 17, 12, "07f000ffc01ffe03ffe07e3f07e3f07e3f07c1f0fc1f0fc1f8fc1f8fc1f8fc1f07c1f07c3f07e3f07e3f03ffe03ffc01ff8007f00" },
            ["1"] = { 17, 12, "00f8003f800ff803ff803ff803ff803df8001f8001f8001f8001f8001f8001f8001f8001f8001f8001f8001f8001f8001f8001f80" },
            ["2"] = { 17, 12, "0ff003ffc03ffe03ffe0387e0203f0003f0003e0007e000fe001fc003f800ff001fc003f8003f0007e0007fff07fff07fff07fff0" },
            ["3"] = { 17, 12, "1ff003ff803ffc03ffe0307e0007e0007e0007e000fc01ff801ff001ffc00ffe0007e0003e0003f0607e07ffe07ffc07ff803fe00" },
            ["4"] = { 17, 12, "007c000fc000fc001fc001fc003fc007fc007fc00ffc01f7c03e7c03e7c07c7c0ffff0ffff8ffff8ffff8007c0007c0007c0007c0" },
            ["5"] = { 17, 12, "1ffe03ffe03ffe03ffe03e0003e0003e0003e0003ff003ffc03ffe03ffe0007e0003f0003f0003e0707e07ffe07ffc07ff803fe00" },
            ["6"] = { 17, 12, "01fe007fe00ffe01ffe01f8003f0003e0007e0007ffc07ffe07fff07fff07e1f87e1f87e1f87e1f83e3f03fff01ffe00ffc007f80" },
            ["7"] = { 17, 12, "7fff87fff87fff87fff0003f0003e0007e000fc000fc001f8001f8001f0003f0003f0007e0007e0007e000fc000fc000fc000fc00" },
            ["8"] = { 17, 12, "07f001ffc03ffe03fff07e3f07e3f07e3f03e3e03ffe00ff801ffc03ffe07e3f07c1f07c1f07c1f87e3f07fff03ffe01ffc007f80" },
            ["9"] = { 17, 12, "07f001ffc03ffc07ffe07e3f07c3f07c3f07c3f07e3f07f7f07fff03fff01fff007bf0003f0003e0207e03ffc03ffc03ff003fe00" },
        } },
    },
    ["Tahoma"] = {
        keys = { bits = 5, em = 20, c = {
            ["J"] = { 8, 5, "7e0007e0000e0000e0000e0000e0000e0000e0000e0000e0000e0000e0001e000fe000f8000" },
            ["C"] = { 12, 5, "0fe003ff007c70070300f0000e0000e0000e0000e0000e0000f0000703007c7003ff000fe00" },
            ["W"] = { 18, 5, "e1e1ce1e1ce1e1c71e1c73f3873f3873f383b3383b3f03f3f03f3f01f1f01e1e01e1e01e1e0" },
            ["A"] = { 12, 5, "0f0000f0001f8001f8001f8003bc0039c0039c0071e007fe007fe00f0f00e0700e0700e0700" },
            ["S"] = { 11, 5, "1fc007fe0078e00f0000e0000f00007e0003fc0007e0000e0000e00c0e00f1e00ffc003f800" },
            ["D"] = { 14, 5, "7fc007fe0071f007078070380703c0701c0701c0701c0701c0703807078070f007fe007fc00" },
        } },
        num = { bits = 5, em = 30, c = {
            ["0"] = { 19, 8, "07fc00ffe01fff03fff83fbf87f1fc7f1fc7e0fc7e0fc7e0fc7e0fc7e0fc7e0fc7e0fc7e0fc7f1fc7f1fc3fbfc3fff81fff00ffe007fc0" },
            ["1"] = { 19, 8, "01f8001f8003f803ff803ff803ff803ff8001f8001f8001f8001f8001f8001f8001f8001f8001f8001f8001f803fffc3fffc3fffc3fffc" },
            ["2"] = { 19, 8, "0ffc03fff03fff83fff83e3fc381fc001fc001fc001fc001f8003f8007f000ff001fe003fc007f800fe001fc003fffe3fffe3fffe3fffe" },
            ["3"] = { 19, 8, "0ffc03fff03fff83fff83c3fc301fc001fc001f8003f803ff003fe003ff003ff8003fc001fc000fc701fc7c3fc7fff87fff87fff01ffc0" },
            ["4"] = { 19, 8, "007f000ff000ff001ff003ff007ff007ff00fbf01fbf01f3f03e3f07c3f0fc3f0ffffeffffeffffeffffe003f0003f0003f0003f0003f0" },
            ["5"] = { 19, 8, "3fffc3fffc3fffc3fffc3f0003f0003f0003f0003ffc03fff03fff83fffc383fc001fc000fc000fc701fc7c3fc7fff87fff07ffe01ff80" },
            ["6"] = { 19, 8, "00ff803ff80fff81fff81fe383f8003f0007ffe07fff07fff87fffc7f1fc7e0fe7e0fe7f0fe7f0fe7f0fc3f9fc3fff81fff80fff003fc0" },
            ["7"] = { 19, 8, "7fffc7fffc7fffc7fffc001fc001fc003f8003f8007f000ff000fe001fc001fc003f8003f8007f0007f000fe000fe001fc001fc003f800" },
            ["8"] = { 19, 8, "07fc01fff03fff87fffc7f1fc7f0fc7f0fc7f9fc3fff83fff00ffe01fff83fffc7e3fc7e0fefe0fefe0fe7f1fc7fffc3fff81fff007fc0" },
            ["9"] = { 19, 8, "07f800ffe03fff03fff87f3f87f1fc7e1fcfe1fcfe0fcfe0fc7f1fc7fffc3fffc1fffc0fffc001f8003f838ff03fff03ffe03ff803fe00" },
        } },
    },
    ["Verdana"] = {
        keys = { bits = 5, em = 20, c = {
            ["J"] = { 9, 6, "3f0003f000070000700007000070000700007000070000700007000070000f000fe000fc000" },
            ["C"] = { 14, 6, "07f001ffc03e3c0780c070000700007000070000700007000070000780c03e3c01ffc00ff00" },
            ["W"] = { 20, 6, "f0f0770f0e70f0e70f0e39f8e39f9c39f9c3999c1f9dc1f9f81f9f81f0f80f0f80f0f00f0f0" },
            ["A"] = { 14, 6, "07800078000fc000fc001fe001ce001ce0038f00387003ff007ff807038070380e01c0e01c0" },
            ["S"] = { 14, 6, "1ff003ff80783807000070000780003f8001ff0003f80003800038060380787807ff003fe00" },
            ["D"] = { 15, 6, "7fc007ff0070f80703c0701c0701c0701c0701c0701c0701c0701c07038070f807ff007fc00" },
        } },
        num = { bits = 6, em = 30, c = {
            ["0"] = { 21, 8, "03fe000fff801fffc01fffc03fdfe03f8fe07f07f07f07f07f07f07f07f07f07f07f07f07f07f07f07f07f07f07f07f03f8fe03fdfe01fffc01fffc00fff8003fe00" },
            ["1"] = { 21, 8, "00fc0000fc0003fc001ffc001ffc001ffc001ffc0000fc0000fc0000fc0000fc0000fc0000fc0000fc0000fc0000fc0000fc0000fc001fffe01fffe01fffe01fffe0" },
            ["2"] = { 21, 8, "07fe001fff801fffc01fffc01e1fe0180fe0000fe0000fe0000fe0000fe0001fc0003f80007f8000ff0001fe0003fc0007f0001fe0003ffff03ffff03ffff03ffff0" },
            ["3"] = { 21, 8, "07fe003fff803fffc03fffe03e1fe0380fe0000fe0000fe0001fc001ff8001ff0001ff8001ffc0000fe00007f00007f07007e07e1fe07fffe07fffc07fff800ffe00" },
            ["4"] = { 21, 8, "003fc0007fc0007fc000ffc001ffc003ffc003ffc007dfc00f9fc01f9fc03f1fc03e1fc07c1fc07ffff87ffff87ffff87ffff8001fc0001fc0001fc0001fc0001fc0" },
            ["5"] = { 21, 8, "1fffe01fffe01fffe01fffe01f80001f80001f80001f80001ffe001fff801fffc01fffe01c1fe00007f00007f00007f0380fe03e1fe03fffe03fffc03fff800ffc00" },
            ["6"] = { 21, 8, "007fc003ffc007ffc00fffc01ff1c01fc0003f80003f7f003fffc03fffe07fffe07f0ff07f07f07f07f07f07f03f07f03f87f03fcfe01fffe00fffc007ff8001fe00" },
            ["7"] = { 21, 8, "3ffff03ffff03ffff03ffff0000fe0000fe0001fc0001fc0003f80003f80007f0000ff0000fe0001fe0001fc0003fc0003f80007f00007f0000fe0001fe0001fc000" },
            ["8"] = { 21, 8, "03fe000fffc01fffe03fffe07f8ff07f07f07f07e03f87e03fffc01fff800fff801fffc03fffe07f0ff07f07f07f07f07f07f07f8ff07fffe03fffe01fff8007fe00" },
            ["9"] = { 21, 8, "03fe000fff001fff803fffc03f9fe07f0fe07f07e07f07f07f07f07f07f07f87f03ffff03ffff01fffe007f7e0000fe0001fc01c7fc01fff801fff001ffe001ff000" },
        } },
    },
    ["Calibri"] = {
        keys = { bits = 5, em = 20, c = {
            ["J"] = { 6, 6, "380003800038000380003800038000380003800038000380003800038000f0000" },
            ["C"] = { 11, 6, "0fc0038e00700007000070000e0000e0000e0000600007000070000386001fc00" },
            ["W"] = { 18, 6, "e1c1ce1e1871e3871e3873e3873f303b7703b7703f3f01f3e01e3e01e1e01e1c0" },
            ["A"] = { 12, 6, "0f0000f0001f0001f8001b8003b80039c0039c0071c007fe0060e00e0e00e0700" },
            ["S"] = { 9, 6, "3e00073000e0000e0000700007c0001e00007000038000380003800e70007e000" },
            ["D"] = { 12, 6, "7f80071c0070e0070e00707007070070700707007070070e0070e0071c007f000" },
        } },
        num = { bits = 4, em = 30, c = {
            ["0"] = { 15, 10, "0fe01ff83ff87efc7c7c7c7ef83ef83ef83ef83ef83ef83ef83efc7c7c7c7efc3ff83ff00fe0" },
            ["1"] = { 15, 10, "03e00fe01fe03fe07fe03be003e003e003e003e003e003e003e003e003e003e03ffc7ffc3ffc" },
            ["2"] = { 15, 10, "1fe07ff87ff871fc00fc00fc00fc00f801f803f003f007e00fc01f803f007e007ffc7ffe7ffe" },
            ["3"] = { 15, 10, "1fe07ff07ff871f800fc00f800f801f81ff03ff01ff801fc00fc007c007c70fc7ff87ff03fe0" },
            ["4"] = { 15, 10, "03f803f807f807f80ff81ff81ef83ef83cf87cf878f8f0f8fffefffefffe00f800f800f800f8" },
            ["5"] = { 15, 10, "3ff83ff83ff83c003c003c003c003fe03ff83ffc00fc007c007c007c007c70fc7ff87ff03fc0" },
            ["6"] = { 15, 10, "07f80ffc1ffc3f183e007c007c007ff07ff87ffc7e7c7c3e7c3e7c3e7c7c7e7c3ffc1ff80fe0" },
            ["7"] = { 15, 10, "7ffc7ffc7ffc007c00fc00f801f801f001f003f003e007e007c00fc00f800f801f801f003f00" },
            ["8"] = { 15, 10, "0ff03ff87ffc7c7c7c7c7c7c7c7c3ff81ff00ff03ff87efc7c7ef83ef83efc7c7ffc3ff81ff0" },
            ["9"] = { 15, 10, "0fe03ff07ff87cfc7c7cf87cf87cf87c7c7c7ffc3ffc1ffc007c007c007c71f87ff07fe03fc0" },
        } },
    },
    ["Consolas"] = {
        keys = { bits = 3, em = 20, c = {
            ["J"] = { 11, 5, "7f87f80380380380380380380380386787f03e0" },
            ["C"] = { 11, 5, "1fc3fc78c700700e00e00e0070070078c3fc1fc" },
            ["W"] = { 11, 5, "e0ee0ee0ee0eeeeeeeeeeffeffefbe7bc7bc71c" },
            ["A"] = { 11, 5, "0e01f01f01b03b83b831871c7fc7fce0ee0ee0e" },
            ["S"] = { 11, 5, "1f87fc71c7007007c01f807c01c01ce1cffc7f0" },
            ["D"] = { 11, 5, "ff0ff8e3ce1ee0ee0ee0ee0ee0ee1ce3cff8ff0" },
        } },
        num = { bits = 4, em = 30, c = {
            ["0"] = { 16, 9, "07f81ffc3ffe3f3f7e1f7c1f7c1ff87ff8fffbffffefffcf7f0f7e1f7c1f3e3f3ffe1ffc07f0" },
            ["1"] = { 16, 9, "03f00ff03ff03ff03ff039f001f001f001f001f001f001f001f001f001f001f03fff3fff3fff" },
            ["2"] = { 16, 9, "0ff01ff83ffc3e7e183e003e003e003e007c00fc00f801f003e007c00f801f003fff7fff7fff" },
            ["3"] = { 16, 9, "1ff03ff83ffc387e003e003e003e00fc0ff80ff80ffe007f001f001f001f707e7ffe7ffc3ff0" },
            ["4"] = { 16, 9, "01fc01fc03fc07fc07fc0ffc1f7c1f7c3e7c3c7c7c7cf87cffffffffffff007c007c007c007c" },
            ["5"] = { 16, 9, "3ffe3ffe3ffe3e003e003e003e003ff03ffc3ffe007e003f001f001f003e007e3ffc3ff83fe0" },
            ["6"] = { 16, 9, "01fe07fe0ffe1f803e003c007c007ff87ffe7fff7e3f7c1f7c1f7c1f7e1f3f3f3ffe1ffc07f0" },
            ["7"] = { 16, 9, "7ffe7ffe7ffe003e007e007c007c00f800f801f001f003e003e007c007c00f800f801f001f00" },
            ["8"] = { 16, 9, "07f81ffe3ffe3e3f7c1f3c1f3e3e3ffc1ff80ffc1ffe3f7f7c1f7c1f7c1f7e3f3ffe3ffc0ff8" },
            ["9"] = { 16, 9, "07f01ffc3ffc7e7e7c3e7c1f7c1f7c1f7e3f7fff3fff0fff001e003e003e00fc3ff83ff03fc0" },
        } },
    },
    ["Impact"] = {
        keys = { bits = 4, em = 20, c = {
            ["J"] = { 7, 5, "7e007e007e007e007e007e007e007e007e007e007e007e007e00fe00fc00f800" },
            ["C"] = { 11, 5, "3f807fc0ffe0fbe0fbe0fbe0fbe0f800f800fbe0fbe0fbe0fbe0ffc07fc03f00" },
            ["W"] = { 16, 5, "ffefffefffffffffffffffffffffffffffff7fff7fff7fff7ffe7ffe7ffe7f7e" },
            ["A"] = { 10, 5, "7f807f807f807f807f807f807f80ffc0ffc0ffc0ffc0ffc0ffc0ffc0ffc0ffc0" },
            ["S"] = { 10, 5, "3f00ff80ffc0ffc0ffc0fc00fe007f003f801fc007c0ffc0ffc0ffc07fc03f00" },
            ["D"] = { 11, 5, "ff80ffc0ffe0ffe0ffe0ffe0ffe0ffe0ffe0ffe0ffe0ffe0ffe0ffe0ffe0ffc0" },
        } },
        num = { bits = 5, em = 30, c = {
            ["0"] = { 17, 7, "0ff801ffe03fff07fff07fff87fff87fff87fff87fff87fff87fff87fff87fff87fff87fff87fff87fff87fff87fff87fff87fff03fff01ffe00ff80" },
            ["1"] = { 12, 7, "03f0007f001ff003ff00fff00fff00fff001ff000ff000ff000ff000ff000ff000ff000ff000ff000ff000ff000ff000ff000ff000ff000ff000ff00" },
            ["2"] = { 16, 7, "0ff003ffc07ffe07fff0ffff0ffff0ffff0ffff001ff001ff003fe003fe007fc007fc00ff801ff001ff003fe003fc007fc007f800ffff0ffff0ffff0" },
            ["3"] = { 17, 7, "1ff803ffe07ffe07fff0ffff0ffff0ffff8ffff0007f000ff007fe007fe007ff000ff0007f8ffff8ffff8ffff8ffff8ffff87fff07fff03ffe00ff80" },
            ["4"] = { 16, 7, "07fe00ffe00ffe00ffe01ffe01ffe01ffe03ffe03ffe03ffe07ffe07ffe0fffe0fffe0fffe0ffff0ffff0ffff0ffff0ffff001fe001fe001fe001fe0" },
            ["5"] = { 17, 7, "7fff07fff07fff07f0007f0007f0007ffe07fff07fff07fff87fff8007f8007f8007f8ffff8ffff87fff87fff87fff87fff87fff03fff01ffe00ff80" },
            ["6"] = { 17, 7, "0ffc01ffe03fff07fff87fff87fff87f8007f8007ffe07fff07fff07fff87fff87fff87fff87fff87fff87fff87fff87fff87fff83fff01ffe00ff80" },
            ["7"] = { 14, 7, "fffc0fffc0fffc003fc003fc007f8007f8007f8007f8007f800ff000ff000ff000ff001fe001fe001fe001fe001fe003fc003fc003fc003fc007fc00" },
            ["8"] = { 17, 7, "0ff801ffe03fff07fff07fff07fff87fff87fff87fff87fff03fff01ffe03fff07fff07fff87fff87fff87fff87fff87fff87fff87fff03ffe00ffc0" },
            ["9"] = { 17, 7, "0ff803ffe07fff07fff07fff87fff87fff87fff87fff87fff87fff87fff87fff87fff83fff81fff8007f8007f87fff87fff87fff07fff03ffe00ff80" },
        } },
    },
    ["Georgia"] = {
        keys = { bits = 5, em = 20, c = {
            ["J"] = { 10, 5, "1fc000780007000070000700007000070000700007000e7000e7000e7000ee0007c000" },
            ["C"] = { 13, 5, "0ff801c780383807038070180f0000f0000f0000f00007000078180383801e7000fe00" },
            ["W"] = { 20, 5, "fc73f7870e3870e38f8c3cf8c1cf9c1dbd81d9d81f9d80f1f00f0f00f0f00e0e006060" },
            ["A"] = { 13, 5, "0700007000078000f8000f8000fc0019c0019c003fe0030e0030f0060700f0780f9f80" },
            ["S"] = { 11, 5, "1fc003bc0071c0070c0070c007c0003f8000fc0003e00c1e00e0e00e0e00f9c00ff800" },
            ["D"] = { 15, 5, "ffe0038f0038380383c0381c0381e0381e0381e0381e0381c0381c0383803c700ffc00" },
        } },
        num = { bits = 5, em = 30, c = {
            ["0"] = { 21, 12, "03fe00fdf81f8fc3f07e3f07e7f07f7f07f7f07f7f07f7f07f7f07f3f07e3f07e1f8fc0fdf803fe0" },
            ["1"] = { 15, 12, "01e0003e0007e007fe0007e0007e0007e0007e0007e0007e0007e0007e0007e0007e000ff007ffe0" },
            ["2"] = { 19, 12, "07fc01e7f03e3f87f1f87f1f87e1f83e3f8003f800fe003f80078001e0003fffc7fffc7fffc7fffc" },
            ["3"] = { 19, 12, "07fc01e7e03e3f07e3f87e1f87e1f83c3f8003f0007e003f8003fe0003f8001f8001fc7c1fcfc1fcfe1fcfc1f87c3f03c7e00ff80" },
            ["4"] = { 19, 12, "003f0007f000ff000ff001ff003bf0073f0073f00e3f01c3f0383f0383f0703f0ffffeffffeffffe003f0003f0003f0003f0003f0" },
            ["5"] = { 18, 12, "1fff81fff81fff81fff83800038000380003ff803ffe03cff0303f8003f8001f8001f87c1f8fc1f8fe3f8fc3f07c7e03cfc00ff00" },
            ["6"] = { 19, 7, "001e000fc003e0007c000f8001f8003f0003f0007ffe07fff07f3f87e1fc7e0fc7e0fc7e0fc7e0fc3e0fc3f1f81f1f80fbf003fc0" },
            ["7"] = { 17, 12, "7fff87fff87fff87fff87007060070600e0001c0001c000380003800070000f0000e0001e0001c000380003800070000f0000e000" },
            ["8"] = { 20, 7, "03fe00f9f01f0fc3f0fc3f0fc3f0fc3f8fc3fcf81fff00ffe007ff80fffc3f7fe7e1fe7e0fe7e07e7e07e7e07c3f07c1f9f007fc0" },
            ["9"] = { 19, 12, "07f800fbe03f1f03f1f87e1f87e0fc7e0fc7e0fc7e0fc7f0fc7f0fc3f9fc1fffc0fff8001f8001f0003f0003e0007c000f0007e000f000" },
        } },
    },
    ["Trebuchet MS"] = {
        keys = { bits = 5, em = 20, c = {
            ["J"] = { 10, 6, "0380003800038000380003800038000380003800038000380003800e7800ff0007e000" },
            ["C"] = { 12, 6, "0fe003fe003ce007000070000f0000e0000e0000e000070000700007ce003fe000fc00" },
            ["W"] = { 17, 6, "e1c38e1c38e1c3873e7073e7073e703f7e03f7e03f7e01e3e01e3c01e3c00c1c00c180" },
            ["A"] = { 12, 6, "06000070000f0000f0001f8001f80019c0039c0039c007fe007fe0070f00e0700e0700" },
            ["S"] = { 10, 6, "3f0007f000f0000e0000f0000780003e0001f00007800038000380067800ff8007e000" },
            ["D"] = { 12, 6, "7f0007fc0071e0070e0070f007070070700707007070070e0070e0073e007fc007f000" },
        } },
        num = { bits = 5, em = 30, c = {
            ["0"] = { 18, 9, "03f800ffc01ffe03f3f03e1f07c0f87c0f87c0f87c0f87c0f87c0f87c0f87c0f87c0f87c0f87c0f83e1f03f3f01ffe00ffc007f00" },
            ["1"] = { 18, 9, "003800078000f8003f800ff800ff800ff800ff800cf8000f8000f8000f8000f8000f8000f8000f8000f8000f8000f8000f8000f80" },
            ["2"] = { 18, 9, "07f001ffc03ffe03e3f01c1f0001f0001f0003f0003e0007e0007c000f8001f8003f0003e0007e000fc001f8001fff83fff83fff8" },
            ["3"] = { 18, 9, "07f001ffc01ffe01e7e00c3e0003e0003e0007e001fc001f8001fc0007e0001f0001f0001f0001f0181f01e3f03ffe03ffc00ff00" },
            ["4"] = { 18, 9, "000e0001e0003e0007e000fe000fe001fe003fe007be00fbe01f3e03e3e03c3e07fffcffffcffffc003e0003e0003e0003e0003e0" },
            ["5"] = { 18, 9, "3ffe03ffe03ffe03e0003e0003e0003ff803ffc03ffe03e3f01c1f0001f0001f0001f0001f0001f0181f01e7f03ffe03ffc00ff00" },
            ["6"] = { 18, 9, "0070001f8003f8007f000fc000f8001f8001f0003ff803ffe03fff07f3f07e1f83c0f83c0f83e0f83e1f83f3f01fff00ffe003f80" },
            ["7"] = { 18, 9, "3fffc3fffc3fff8001f8001f0003f0003e0007e0007c000fc000f8001f8001f0003f0003e0007e0007c000fc000f8000f8001f800" },
            ["8"] = { 18, 9, "07f800ffc01ffe03f3f03e1f03e1f03f3f01fbe00ffc00ff801ffc01ffe03e3f07e1f07c0f87c0f87e1f83f3f03fff01ffe007f80" },
            ["9"] = { 18, 9, "07f000ffc01ffe03f3f03e1f07c0f07c0f87c0f83e1f83f3f81fff81fff007ff0003f0003e0007c000fc001f8007f0007e0003800" },
        } },
    },
    ["Comic Sans MS"] = {
        keys = { bits = 5, em = 20, c = {
            ["J"] = { 13, 7, "1ff801ff8001c0001c0001c0001c0001c0001c0001c00e3800e3800738007b8003f8001f000" },
            ["C"] = { 12, 7, "03f000ff001f7001c70038000780007000070000e0000e0000e0000f070079f003fc001f800" },
            ["W"] = { 20, 7, "70303707837878738f8738f8738f8e1dfce1ddce1dddc1fddc0f9d80f9f80f0f80f0f00f0f0" },
            ["A"] = { 14, 7, "00e0001e0001e0003e0007e0007f000f7000e7001ff003ff003f7803838078380703c0701c0" },
            ["S"] = { 14, 7, "07f000ff801e0003c000380003c0001fe000ff8000780003c0003c07038078f807ff001fc00" },
            ["D"] = { 14, 7, "380007e0007fc0073e0070f007078070380703c0701c0701c0703807038078f007ff001fc00" },
        } },
        num = { bits = 5, em = 30, c = {
            ["0"] = { 18, 9, "03f800ffc01fff03fff03f3f87e0f87c0fcfc07cf807cf807cf807cf807cf807cf807cf807cf807cfc0fc7c0f87e1f87f3f83fff01ffe00ffc007f80" },
            ["1"] = { 18, 9, "00e0003f0007f000ff001ff001ff000ff0003f0003f0003f0003f0003f0003e0003e0003e0003e0003e0003e0003e000ffc01ffc01ffc01ffc0" },
            ["2"] = { 18, 9, "03f800ffe01fff03fff07f3f87e1f83c1f8001f8003f0007f000fe003fc007f800fe001fc003f0003e0007e0007c0007fff07fff87fff83fff0" },
            ["3"] = { 18, 9, "07f001ffc03ffe03fff03f3f03c1f0001f0001f000ff007fe007fc007fe007ff0007f0001f8001f8000f8780f87c1f87e3f07fff03ffe01ffc007f00" },
            ["4"] = { 18, 9, "003c0007e000fe001fe001fe003fe007fe007fe00ffe01fbe03f3e03f3e07e3e0ffffcffffcffffcffffc003e0003e0003e0003e0003e0003e0" },
            ["5"] = { 18, 9, "7fff87fff87fff83fff03e0007e0007ffc07ffe07fff07fff87f9f87e0f87c0fc7807c0007c0007c000fc000f8781f87e3f87fff07ffe01ffc00ff00" },
            ["6"] = { 18, 9, "0070000f8001f8007f0007f000fe001f8003f8003f0003ff807ffe07fff07fff87e1f87c0f87c0f87c0f87c0f87e0f87f3f83fff01fff00ffc007f80" },
            ["7"] = { 18, 9, "7fffcffffcffffcffffc001f8003f0007e0007e000fc000fc001f8001f8003f0003f0003e0007e0007c000fc000fc000f8001f8001f8001f0000e000" },
            ["8"] = { 18, 9, "03f800ffc01ffe03fff03f3f07e1f07e1f07e1f03f7f03ffe01ffc01ffe03fff07f7f87e1f87c0f87c0f87c0f87c0f87e1f87fff83fff01ffe007f80" },
            ["9"] = { 18, 9, "07f801ffc03ffe07fff07e3f87c1f8fc0f8f80fcf80fcfc0fcfc0f87e3f87fff83fff81fff007ff0003f0007e001fc00ff803ff003fe003f8003e000" },
        } },
    },
    ["Courier New"] = {
        keys = { bits = 3, em = 20, c = {
            ["J"] = { 12, 5, "0ff00c00c00c00c00c60c60c60c61c3b81f0" },
            ["C"] = { 12, 5, "1fe38e706600600e00e0060060070738e0f8" },
            ["W"] = { 12, 5, "fbfe066066e66fe6fe6fe7fe7bc7bc79c79c" },
            ["A"] = { 12, 5, "7f00f01f819819839c30c3fc70e606606f9f" },
            ["S"] = { 12, 5, "1fe39e30e3003801f801c00600660670c7f8" },
            ["D"] = { 12, 5, "7f830c30630630330330330330630630c7f8" },
        } },
        num = { bits = 5, em = 30, c = {
            ["0"] = { 18, 6, "03f000ffc00ffc01f3e01e1e03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f03c0f01e1e01f3e00ffc00ffc003f00" },
            ["1"] = { 18, 6, "00e000fe003fe003fe003fe0001e0001e0001e0001e0001e0001e0001e0001e0001e0001e0001e003fff03fff03fff0" },
            ["2"] = { 18, 6, "07f000ffc01ffe03f3e03c1f03c0f0381f0001f0003e0007c000fc003f0007e000fc001f8003e0007ffe07fff07fff0" },
            ["3"] = { 18, 6, "07f800ffc01ffe03e1f01c0f0000f0001f003fe003fc003fe0003f0000f0000f0000f8000f03c1f07fff03ffe01ff80" },
            ["4"] = { 18, 6, "007c000fc001fc001fc003fc007fc007fc00fbc00fbc01f3c03e3c03fff03fff03fff0003c0003c001ff001ff001ff0" },
            ["5"] = { 18, 6, "1ffe01ffe01ffe01e0001e0001e0001ff801ffc01ffe01f1f0000f0000f0000f8000f0380f07c1f03ffe03ffc00ff80" },
            ["6"] = { 18, 6, "007f001ff803ff807e700f8000f0001f0001ff801ffe01fff01fdf01f0f81f0781e0781f0f80f9f00fff007fe001fc0" },
            ["7"] = { 18, 6, "3fff03fff03fff03c1f03c1e0001e0003e0003c0003c0007c0007800078000f8000f0000f0001f0001e0001e0001e00" },
            ["8"] = { 18, 6, "07f800ffc01ffe01f3e03e1f03c0f03e1f01f3e01ffe00ffc01ffe03f3f03c0f03c0f03c0f03e1f01ffe00ffc007f80" },
            ["9"] = { 18, 6, "03f8007fc00ffe01f3e01e1f01e0f01e0f01e0f81e1f81f3f80fff807ff803ff0001f0003f01cfe01ffc01ff800fe00" },
        } },
    },
    ["Bahnschrift"] = {
        keys = { bits = 5, em = 20, c = {
            ["J"] = { 10, 6, "038000380003800038000380003800038000380003800038000380067800ff0007e000" },
            ["C"] = { 12, 6, "1f8003fe0079e0070f0070000700007000070000700007000070f0079e003fe001f800" },
            ["W"] = { 18, 6, "e1c38e1c38f1c7873e7073e7073e70776703f7e03f7e03f7e03e3e01e3c01e3c01e3c0" },
            ["A"] = { 13, 6, "070000f0000f8000f8001dc001dc001dc0038e0038e007fe007ff0070700f0780e0380" },
            ["S"] = { 12, 6, "1fc003fe0078e007000070000780003f8001fe0000f00007000070070f007fe003fc00" },
            ["D"] = { 13, 6, "7fc007fe0070f00707007070070700707007070070700707007070070f007fe007fc00" },
        } },
        num = { bits = 4, em = 30, c = {
            ["0"] = { 16, 9, "0ff01ffc3ffc3ffe7e7e7e3e7e3e7e3e7e3e7e3e7e3e7e3e7e3e7e3e7e3e7e3e7e7e3ffe3ffc1ffc0ff0" },
            ["1"] = { 10, 9, "3f007f00ff00ff00ff005f001f001f001f001f001f001f001f001f001f001f001f001f001f001f001f00" },
            ["2"] = { 15, 9, "0ff01ff83ffc7ffc7e7e7c7e007e007c00fc01fc03f803f007e00fc01fc01f803f007ffe7ffe7ffe7ffe" },
            ["3"] = { 16, 9, "0ff01ff83ffc7ffc7e7c7c7c007c007c07fc07f807f807fc007c007e007efc7e7c7e7ffc3ffc1ff80ff0" },
            ["4"] = { 17, 9, "01f801f803f003f003e007e007c00fc00f801fbe1fbe3f3e3f3e7e3e7fff7fff7fff7fff003e003e003e" },
            ["5"] = { 16, 9, "3ffc3ffc3ffc3ffc3e003e003e003ff03ffc3ffc3ffe3e7e3c3e003e003e7e3e3e7e3ffe3ffc1ff807f0" },
            ["6"] = { 15, 9, "03f003f007e007e007c00fc00f801f801ff03ff83ffc7ffc7e7c7c7c7c7e7c7c7e7c7ffc3ff81ff80fe0" },
            ["7"] = { 15, 9, "7ffc7ffc7ffc7ffc7cfc7cf87cf801f801f801f001f003f003f003e003e007e007c007c00fc00fc00f80" },
            ["8"] = { 17, 9, "07f01ffc3ffe3ffe3e3e3e3e3e3e3e3e1ffc0ff81ffc3ffe3e7e7c3f7c1f7c3f7e3f3ffe3ffe1ffc07f0" },
            ["9"] = { 15, 9, "0fe01ff83ffc7ffc7e7c7c7c7c7e7e7c7ffc3ffc3ffc0ff801f801f001f003f003e007e007c00fc00f80" },
        } },
    },
    ["Arial Black"] = {
        keys = { bits = 5, em = 20, c = {
            ["J"] = { 13, 7, "01f0001f0001f0001f0001f0001f0001f0001f0001f00f9f00f9f00fff00fff007fe003fc00" },
            ["C"] = { 16, 7, "0ff001ffc03ffe07f7e07e3e07c000fc000fc000fc0007c1c07e3f07e7e03ffe01ffc00ff80" },
            ["W"] = { 20, 7, "f9f9ff9f9ff9f9ffbfdffffff7fffe7fffe7fffe7fffe7fffe3f9fc3f9fc3f9fc3f8fc3f0fc" },
            ["A"] = { 16, 7, "07e0007e000ff000ff001ff001ff801ff803ffc03e7c03ffc07ffe07ffe0ffff0fc3f0f81f0" },
            ["S"] = { 14, 7, "1fe003ff007ff807cf807cf807fc007ff003ff800ffc000fc0fcfc0fcfc07ff807ff001fe00" },
            ["D"] = { 16, 7, "7ff007ffc07ffc07e7e07e3e07e3e07e3f07e3f07e3f07e3e07e3e07e7e07ffc07ffc07ff00" },
        } },
        num = { bits = 5, em = 30, c = {
            ["0"] = { 20, 11, "03fc00fff01fff83fffc3f9fc7f0fe7f0fe7f0fe7f0fe7f0fe7f0fe7f0fe7f0fe7f0fe7f0fe7f0fe7f0fe3f9fc3fffc1fff80fff003fc0" },
            ["1"] = { 20, 11, "007e000fe000fe001fe007fe01ffe03ffe03ffe03ffe03efe038fe000fe000fe000fe000fe000fe000fe000fe000fe000fe000fe000fe0" },
            ["2"] = { 20, 11, "07fe01fff83fffc3fffc7f9fe7f0fe7f0fe000fe001fe003fc007fc00ff803ff007fc00ff801ff003fc003fffe7fffe7fffe7fffeffffe" },
            ["3"] = { 20, 11, "07fe00fff03fff83fffc7f9fc7f1fc1f1fc003fc00ff800ff000ff801ffc001fe000fe000fe7f0fe7f0fe7f9fe3fffc3fffc0fff807fe0" },
            ["4"] = { 20, 11, "003f8003f8007f800ff801ff803ff807ff807ff80fdf81fdf83f9f87f1f8fe1f8fffffffffffffffffffffffff001f8001f8001f8001f8" },
            ["5"] = { 20, 11, "1fffc1fffc1fffc1fffc3fffc3f8003f8003ffe03fff83fffc7fffe7f9fe020fe000fe000fe7f0fe7f0fe7f9fe3fffc3fff80fff007fc0" },
            ["6"] = { 20, 11, "03fe00fff81fffc3fffc3fdfe7f8fe7f0007f0007f7e07fff87fffc7fffe7f9fe7f0fe7f07e7f07e7f0fe3f9fe3fffe1fffc0fff803fe0" },
            ["7"] = { 20, 11, "7fffe7fffe7fffe7fffe7fffe001fc003f8003f0007f000fe000fc001fc001fc003f8003f8003f8007f0007f0007f0007f0007f000fe00" },
            ["8"] = { 20, 11, "07fe00fff03fffc3fffc7f9fe7f0fe7f0fe3f9fc3fffc1fff81fff83fffc7f9fe7f0fe7f0fe7f0fe7f0fe7f9fe7fffc3fffc1fff807fe0" },
            ["9"] = { 20, 11, "07fc01fff03fff87fffc7f9fc7f0fe7e0fefe0fe7f0fe7f9fe7fffe3fffe1fffe07efe000fe000fe7f1fe7fbfc3fffc3fff81fff007fc0" },
        } },
    },
}

-- Turn the hex rows of one font into span lists (decoded once per font).
function FONT.prepare(name)
    local cached = FONT.cache[name]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local src = FONT.data[name]
    if src == nil then
        FONT.cache[name] = false
        return nil
    end

    local set = {}
    for _, part_name in ipairs({ "keys", "num" }) do
        local def  = src[part_name]
        local bits = def.bits
        local full = bits * 4
        local glyphs = {}
        local max_w, max_h, min_top = 1, 1, 999
        for ch, raw in pairs(def.c) do
            local adv, top, hex = raw[1], raw[2], raw[3]
            local rows = {}
            local h = math.floor(#hex / bits)
            for row = 1, h do
                local v = tonumber(hex:sub((row - 1) * bits + 1, row * bits), 16) or 0
                local spans = {}
                local x = 0
                while x < full do
                    if ((v >> (full - 1 - x)) & 1) == 1 then
                        local s = x
                        while x < full and ((v >> (full - 1 - x)) & 1) == 1 do
                            x = x + 1
                        end
                        spans[#spans + 1] = { s, x }
                    else
                        x = x + 1
                    end
                end
                rows[row] = spans
            end
            glyphs[ch] = { adv = adv, top = top, h = h, rows = rows }
            if adv > max_w then max_w = adv end
            if h > max_h then max_h = h end
            if top < min_top then min_top = top end
        end
        set[part_name] = { glyphs = glyphs, w = max_w, h = max_h, top = min_top }
    end

    FONT.cache[name] = set
    return set
end

function FONT.glyph(glyph, x, y, top_ref, r, gg, b, a)
    local dy = y + glyph.top - top_ref
    for row = 1, glyph.h do
        local spans = glyph.rows[row]
        if spans[1] ~= nil then
            local py = dy + row - 1
            for i = 1, #spans do
                local s = spans[i]
                fill_rect(x + s[1], py, s[2] - s[1], 1, r, gg, b, a)
            end
        end
    end
end

function FONT.word(part, text, cx, y, r, gg, b, a)
    local w = 0
    for i = 1, #text do
        local glyph = part.glyphs[text:sub(i, i)]
        if glyph ~= nil then w = w + glyph.adv end
    end
    local x = floor(cx - w / 2)
    for i = 1, #text do
        local glyph = part.glyphs[text:sub(i, i)]
        if glyph ~= nil then
            FONT.glyph(glyph, x, y, part.top, r, gg, b, a)
            x = x + glyph.adv
        end
    end
end

local function render_velocity(now)
    local step = clamp((now - wasd_last) * 14, 0, 1)
    wasd_last = now

    if not ui.get_bool("Velocity indicator") then return end

    local me = entity.get_local_player()
    if me == nil or not entity.is_alive(me) then return end

    local okv, vx, vy = pcall(entity.get_velocity, me)
    if not okv or type(vx) ~= "number" then return end
    if type(vy) ~= "number" then vy = 0 end
    local speed = math.sqrt(vx * vx + vy * vy)

    local sw, sh = client.screen_size()
    local cx = sw / 2
    local r, g, b = col("Velocity color", 0.62, 0.32, 1.0, 1.0)

    -- keybinds fade out and the speed number slides down into their place
    local want_keys = ui.get_bool("Velocity keybinds")
    keys_vis = clamp(keys_vis + ((want_keys and 1 or 0) - keys_vis) * step, 0, 1)
    local kv = keys_vis

    -- selected font
    local fi = 0
    if ui.get_combo then
        local okc, v = pcall(ui.get_combo, "Velocity font")
        if okc and type(v) == "number" then fi = v end
    end
    fi = clamp(fi + 1, 1, #FONT.names)
    local fset = nil
    if fi > 1 then fset = FONT.prepare(FONT.names[fi]) end

    local text = tostring(floor(speed))

    local num_h   = fset and fset.num.h or 21
    local key_h   = fset and fset.keys.h or 14
    local key_w   = fset and fset.keys.w or 10
    local col_gap = 11
    local row_gap = 10

    local band_top = floor(sh - 210)
    local band_h   = num_h + 12 + (2 * key_h + row_gap)
    local y_num    = floor(band_top + (band_h - num_h) * (1 - kv))

    -- speed number
    if fset then
        FONT.word(fset.num, text, cx + 2, y_num + 2, 0, 0, 0, 90)
        FONT.word(fset.num, text, cx, y_num, 242, 242, 248, 255)
    else
        draw_text_glyphs(cx + 2, y_num + 2, text, 3, 3, 0, 0, 0, 90)
        draw_text_glyphs(cx, y_num, text, 3, 3, 242, 242, 248, 255)
    end

    -- keystrokes in a 3x2 grid under the number
    if kv > 0.01 then
        local grid_w = 3 * key_w + 2 * col_gap
        local gx     = floor(cx - grid_w / 2)
        local gy     = band_top + num_h + 12
        local ga     = floor(255 * kv)

        for i = 1, #KEY_GRID do
            local label = KEY_GRID[i][1]
            local st    = wasd[KEY_GRID[i][2]]
            local bx    = gx + KEY_GRID[i][3] * (key_w + col_gap)
            local by    = gy + KEY_GRID[i][4] * (key_h + row_gap)

            st.level = clamp(st.level + ((st.down and 1 or 0) - st.level) * step, 0, 1)
            local lv = st.level

            local cr = floor(232 + (r - 232) * lv)
            local cg = floor(232 + (g - 232) * lv)
            local cb = floor(238 + (b - 238) * lv)

            if fset then
                local gph = fset.keys.glyphs[label]
                if gph ~= nil then
                    local kx = bx + floor((key_w - gph.adv) / 2)
                    FONT.glyph(gph, kx + 1, by + 1, fset.keys.top, 0, 0, 0, floor(100 * kv))
                    FONT.glyph(gph, kx, by, fset.keys.top, cr, cg, cb, ga)
                end
            else
                draw_glyph(bx + 1, by + 1, GLYPHS[label], 2, 0, 0, 0, floor(100 * kv))
                draw_glyph(bx, by, GLYPHS[label], 2, cr, cg, cb, ga)
            end
        end
    end
end

local function render_tracers(now)
    if #tracers == 0 then return end
    local enabled = ui.get_bool("Tracer enabled")
    local life    = clamp(ui.get_float("Tracer lifetime"), 0.5, 6.0)
    local glow    = clamp(ui.get_int("Tracer glow"), 1, 10)
    local pulse   = ui.get_bool("Tracer pulse")
    local r, g, b = col("Tracer color", 0.35, 0.65, 1.0, 1.0)
    local keep    = {}

    for _, tr in ipairs(tracers) do
        local age = now - tr.born
        if age <= life then
            if enabled then
                local fade = 1.0 - age / life
                local alpha = floor(clamp(fade * fade, 0, 1) * 255)
                if pulse then
                    alpha = floor(alpha * (0.55 + 0.45 * (sin(now * 8.0) * 0.5 + 0.5)))
                end
                if alpha > 3 then
                    local sx, sy, sok = client.world_to_screen(tr.sx, tr.sy, tr.sz)
                    local ex, ey, eok = client.world_to_screen(tr.ex, tr.ey, tr.ez)
                    if sok and eok then
                        glow_line(sx, sy, ex, ey, r, g, b, alpha, glow)
                    end
                end
            end
            keep[#keep + 1] = tr
        end
    end
    tracers = keep
end

local function render_damage(now)
    if not ui.get_bool("Damage indicator") or #damage == 0 then return end
    local r, g, b = col("Damage color", 1.0, 0.4, 0.4, 1.0)
    local dur     = clamp(ui.get_float("Damage duration"), 0.5, 4.0)
    local drift   = clamp(ui.get_int("Damage drift"), 20, 200)
    local keep    = {}

    for _, d in ipairs(damage) do
        local age = now - d.born
        if age < dur then
            local t     = age / dur
            local alpha = floor(clamp((1.0 - t) * (1.0 - t), 0, 1) * 255)
            local sx, sy, ok = client.world_to_screen(d.wx, d.wy, d.wz)
            if not ok then
                sx, sy = d.sx, d.sy
            end
            if alpha > 3 then
                local ix = floor(sx + d.ox)
                local iy = floor(sy + d.oy - t * drift)
                draw.text(ix, iy, d.text, r, g, b, alpha)
            end
            keep[#keep + 1] = d
        end
    end
    damage = keep
end

local function render_nimb(now)
    if not ui.get_bool("Nimb enabled") then
        nimb_pos.x, nimb_pos.y, nimb_pos.z = nil, nil, nil
        return
    end
    local me = entity.get_local_player()
    if me == nil or not entity.is_alive(me) then
        nimb_pos.x, nimb_pos.y, nimb_pos.z = nil, nil, nil
        return
    end
    local ox, oy, oz = player_origin(me)
    if not ox then return end

    local _, _, ez = client.get_eye_pos()
    local height = clamp(ui.get_int("Nimb height"), 0, 60)
    local radius = clamp(ui.get_int("Nimb radius"), 6, 48)
    local tx, ty, tz = ox, oy, (ez or oz + 72) - height

    if nimb_pos.x == nil then
        nimb_pos.x, nimb_pos.y, nimb_pos.z = tx, ty, tz
    else
        nimb_pos.x = lerp(nimb_pos.x, tx, 0.35)
        nimb_pos.y = lerp(nimb_pos.y, ty, 0.35)
        nimb_pos.z = lerp(nimb_pos.z, tz, 0.35)
    end

    local r, g, b = col("Nimb color", 0.5, 0.8, 1.0, 1.0)
    local glow    = clamp(ui.get_int("Nimb glow"), 0, 8)
    local thick   = clamp(ui.get_int("Nimb thickness"), 1, 5)
    local pulse   = ui.get_bool("Nimb pulse") and (sin(now * 9.5) * 0.5 + 0.5) or 1.0
    local base_a  = floor(140 + pulse * 90)
    local glow_a  = floor(30 + pulse * 40)

    local segs   = 48
    local step   = (pi * 2) / segs
    local yaw    = rad(real_yaw)
    local points = {}

    for i = 0, segs - 1 do
        local t  = i * step + yaw
        local wx = nimb_pos.x + cos(t) * radius
        local wy = nimb_pos.y + sin(t) * radius
        local sx, sy, ok = client.world_to_screen(wx, wy, nimb_pos.z)
        points[i] = ok and { sx, sy } or nil
    end

    for i = 0, segs - 1 do
        local a = points[i]
        local c = points[(i + 1) % segs]
        if a and c then
            if glow > 0 then
                for gi = glow, 1, -1 do
                    local k  = 1.0 - gi / (glow + 1)
                    local ga = floor(glow_a * k * k)
                    if ga > 2 then
                        draw.line(a[1] - gi, a[2],      c[1] - gi, c[2],      r, g, b, ga)
                        draw.line(a[1] + gi, a[2],      c[1] + gi, c[2],      r, g, b, ga)
                        draw.line(a[1],      a[2] - gi, c[1],      c[2] - gi, r, g, b, ga)
                        draw.line(a[1],      a[2] + gi, c[1],      c[2] + gi, r, g, b, ga)
                    end
                end
            end
            for t = 0, thick - 1 do
                local off = t - floor(thick / 2)
                draw.line(a[1] + off, a[2],      c[1] + off, c[2],      r, g, b, base_a)
                draw.line(a[1],       a[2] + off, c[1],       c[2] + off, r, g, b, base_a)
            end
        end
    end
end

local CUBE_EDGES = {
    { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
    { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
    { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
}

local function render_cubes(now)
    if #cubes == 0 then return end
    local enabled = ui.get_bool("Cubes enabled")
    local r, g, b = col("Cubes color", 0.7, 0.5, 1.0, 1.0)
    local glow    = clamp(ui.get_int("Cubes glow"), 1, 10)
    local keep    = {}

    for _, p in ipairs(cubes) do
        local age  = now - p.born
        local frac = age / p.life
        if frac < 1.0 then
            if enabled then
                local drag = math.exp(-age * 0.4)
                local wx   = p.wx + p.vx * age * drag * 60
                local wy   = p.wy + p.vy * age * drag * 60
                local wz   = p.wz + p.vz * age * drag * 60
                local ease_in  = min(1.0, age / 0.10)
                local ease_out = 1.0 - frac * frac * frac
                local alpha    = floor(clamp(ease_in * ease_out, 0, 1) * 200)
                if alpha > 1 then
                    local s    = p.size * (1.0 - frac * 0.4)
                    local arx  = p.rx + p.rxs * age
                    local ary  = p.ry + p.rys * age
                    local arz  = p.rz + p.rzs * age
                    local cax, sax = cos(arx), sin(arx)
                    local cay, say = cos(ary), sin(ary)
                    local caz, saz = cos(arz), sin(arz)

                    local verts = {
                        { -s, -s, -s }, { s, -s, -s }, { s, s, -s }, { -s, s, -s },
                        { -s, -s,  s }, { s, -s,  s }, { s, s,  s }, { -s, s,  s },
                    }
                    local proj = {}
                    for vi = 1, 8 do
                        local x0, y0, z0 = verts[vi][1], verts[vi][2], verts[vi][3]
                        local x1 = cay * caz * x0 - cay * saz * y0 + say * z0
                        local y1 = (sax * say * caz + cax * saz) * x0 + (-sax * say * saz + cax * caz) * y0 - sax * cay * z0
                        local z1 = (-cax * say * caz + sax * saz) * x0 + (cax * say * saz + sax * caz) * y0 + cax * cay * z0
                        local sx, sy, ok = client.world_to_screen(wx + x1, wy + y1, wz + z1)
                        if ok then proj[vi] = { sx, sy } end
                    end
                    for _, e in ipairs(CUBE_EDGES) do
                        local a, c = proj[e[1]], proj[e[2]]
                        if a and c then
                            glow_line(a[1], a[2], c[1], c[2], r, g, b, alpha, glow)
                        end
                    end
                end
            end
            keep[#keep + 1] = p
        end
    end
    cubes = keep
end

local function render_sparks(now)
    if #sparks == 0 then return end
    local enabled = ui.get_bool("Sparks enabled")
    local glow    = clamp(ui.get_int("Sparks glow"), 0, 8)
    local dt      = 0.015
    local keep    = {}

    for _, sp in ipairs(sparks) do
        local age  = now - sp.born
        local frac = age / sp.life
        if frac < 1.0 then
            if enabled then
                sp.x = sp.x + sp.vx * dt
                sp.y = sp.y + sp.vy * dt
                sp.z = sp.z + sp.vz * dt
                sp.vz = sp.vz - 80.0 * dt

                local sx, sy, ok = client.world_to_screen(sp.x, sp.y, sp.z)
                local tx, ty, tok = client.world_to_screen(
                    sp.x - sp.vx * dt * 4,
                    sp.y - sp.vy * dt * 4,
                    sp.z - sp.vz * dt * 4)
                if ok then
                    local fade  = 1.0 - frac * frac
                    local alpha = floor(clamp(fade, 0, 1) * 220)
                    local ex = tok and tx or sx
                    local ey = tok and ty or sy
                    if glow > 0 then
                        for gi = glow, 1, -1 do
                            local k  = gi / glow
                            local ga = floor(alpha * math.exp(-k * 2.5) * 0.3)
                            if ga > 2 then
                                draw.line(sx - gi, sy,      ex - gi, ey,      sp.r, sp.g, sp.b, ga)
                                draw.line(sx + gi, sy,      ex + gi, ey,      sp.r, sp.g, sp.b, ga)
                                draw.line(sx,      sy - gi, ex,      ey - gi, sp.r, sp.g, sp.b, ga)
                                draw.line(sx,      sy + gi, ex,      ey + gi, sp.r, sp.g, sp.b, ga)
                            end
                        end
                    end
                    draw.line(sx, sy, ex, ey, sp.r, sp.g, sp.b, alpha)
                    draw.circle_filled(sx, sy, max(1, floor(3 * fade)), sp.r, sp.g, sp.b, floor(alpha * 0.6))
                end
            end
            keep[#keep + 1] = sp
        end
    end
    sparks = keep
end

local function render_souls(now)
    if #souls == 0 then return end
    local enabled = ui.get_bool("Souls enabled")
    local pr, pg, pb = col("Souls color", 0.55, 0.85, 1.0, 1.0)
    local keep = {}

    for _, p in ipairs(souls) do
        local age  = now - p.born
        local frac = age / p.life
        if frac < 1.0 then
            if enabled then
                local drag = math.exp(-age * 0.3)
                local wx   = p.wx + p.vx * age * drag * 60
                local wy   = p.wy + p.vy * age * drag * 60
                local wz   = p.wz + p.vz * age * drag * 60
                local sx, sy, ok = client.world_to_screen(wx, wy, wz)
                if ok then
                    local ease_in  = min(1.0, age / 0.12)
                    local ease_out = 1.0 - frac * frac
                    local base_a   = clamp(ease_in * ease_out, 0, 1)
                    local alpha    = floor(base_a * 255)
                    local radius   = max(2, floor(p.size * (1.0 - frac * 0.5)))
                    for i = 20, 1, -1 do
                        local t  = i / 20
                        local ra = floor(base_a * (1.0 - t) * (1.0 - t) * 220)
                        if ra > 0 then
                            draw.circle_filled(sx, sy, max(1, floor(radius * t)), pr, pg, pb, ra)
                        end
                    end
                    draw.circle_filled(sx, sy, max(1, floor(radius * 0.18)), pr, pg, pb, alpha)
                end
            end
            keep[#keep + 1] = p
        end
    end
    souls = keep
end

local function render_rockets(now)
    if #rockets == 0 then return end
    local enabled = secret_on()
    local keep = {}

    for _, r in ipairs(rockets) do
        local age  = now - r.born
        local frac = age / r.life
        if frac < 1.0 then
            if enabled then
                local drag = math.exp(-age * 0.25)
                local wx = r.x + r.vx * age * drag
                local wy = r.y + r.vy * age * drag
                local wz = r.z + r.vz * age * drag

                local h    = 26 * (r.size / 5)
                local sway = sin(now * 5.0 + r.phase) * 0.4
                local dirx, diry = cos(r.phase), sin(r.phase)

                local bx, by, bok = client.world_to_screen(wx, wy, wz)
                local tx, ty, tok = client.world_to_screen(
                    wx + dirx * sway * h * 0.3,
                    wy + diry * sway * h * 0.3,
                    wz + h)

                if bok and tok then
                    local dx, dy = tx - bx, ty - by
                    local len = math.sqrt(dx * dx + dy * dy)
                    if len > 2 then
                        local ux, uy = dx / len, dy / len
                        local px, py = -uy, ux
                        local ppu = len / h

                        local fade = 1.0 - frac
                        if age < 0.15 then fade = age / 0.15 end
                        local a = floor(clamp(fade, 0, 1) * 235)

                        if a > 3 then
                            local rad = 3.0 * ppu
                            if rad < 0.8 then rad = 0.8 end

                            local half = floor(rad)
                            if half < 1 then half = 1 end
                            if half > 40 then half = 40 end
                            local off = rad / half

                            for i = -half, half do
                                local o = i * off
                                draw.line(bx + px * o, by + py * o,
                                          tx + px * o * 0.75, ty + py * o * 0.75,
                                          228, 172, 138, a)
                            end

                            draw.circle_filled(tx, ty, rad * 1.3, 236, 150, 150, a)

                            local br = rad * 1.5
                            local bx0, by0 = bx - ux * br * 0.4, by - uy * br * 0.4
                            draw.circle_filled(bx0 + px * br * 0.9, by0 + py * br * 0.9, br, 226, 166, 132, a)
                            draw.circle_filled(bx0 - px * br * 0.9, by0 - py * br * 0.9, br, 226, 166, 132, a)
                        end
                    end
                end
            end
            keep[#keep + 1] = r
        end
    end
    rockets = keep
end

on("on_render", function()
    update_fps()
    local now = client.curtime()
    render_watermark(now)
    render_tracers(now)
    render_velocity(now)
    render_damage(now)
    render_nimb(now)
    render_cubes(now)
    render_sparks(now)
    render_souls(now)
    render_rockets(now)
end)

on("on_ragebot_target", function(ent, valid, damage, hitbox, hitchance, required, fov, distance, x, y, z)
    -- hitchance comes either as 0..100 or 0..1 depending on build; normalize once
    local hc = hitchance or 0
    if hc > 0 and hc <= 1 then hc = hc * 100 end

    rage.time     = client.curtime()
    rage.target   = ent
    rage.valid    = (valid == true) or (type(valid) == "number" and valid ~= 0)
    rage.damage   = damage or 0
    rage.hitbox   = hitbox or 0
    rage.hc       = hc
    rage.required = required or 0
    rage.fov      = fov or 0
    rage.dist     = distance or 0
    rage.x, rage.y, rage.z = x or 0, y or 0, z or 0
end)

-- ============================== EVENTS ==============================

on("on_weapon_fire", function(player, weapon)
    local now = client.curtime()

    if not is_local(player) then return end

    local ex, ey, ez = client.get_eye_pos()
    shot_eye.x, shot_eye.y, shot_eye.z = ex, ey, ez
    shot_eye.time = now
end)

on("on_bullet_impact", function(idx, x, y, z)
    local now = client.curtime()
    if not is_local(idx) then return end

    local sx, sy, sz
    if now - shot_eye.time <= 0.5 then
        sx, sy, sz = shot_eye.x, shot_eye.y, shot_eye.z
    else
        sx, sy, sz = client.get_eye_pos()
    end
    if not sx then return end
    tracers[#tracers + 1] = {
        sx = sx, sy = sy, sz = sz,
        ex = x,  ey = y,  ez = z,
        born = now,
    }
end)

on("on_player_hurt", function(attacker, victim, dmg, health, hitgroup)
    local now = client.curtime()
    if not is_local(attacker) then return end

    local idx = victim_index(victim)
    local wx, wy, wz
    if idx then
        wx, wy, wz = player_origin(idx)
    end
    if not wx then return end

    local head_z = wz + 64

    local sx, sy = client.world_to_screen(wx, wy, head_z)

    last_hurt[idx] = { x = wx, y = wy, z = wz }

    damage[#damage + 1] = {
        text = "-" .. tostring(dmg),
        wx = wx, wy = wy, wz = head_z,
        sx = sx or 0, sy = sy or 0,
        ox = math.random(-40, 40),
        oy = math.random(-40, 40),
        born = now,
    }
end)

on("on_player_death", function(attacker, victim)
    if is_local(attacker) and ui.get_bool("Kill message") then
        client.console_exec("say ★ hts.lua ★")
    end

    local idx = victim_index(victim)
    local pos = idx and (last_hurt[idx] or last_origin[idx]) or nil
    if not pos and idx then
        local x, y, z = player_origin(idx)
        if x then pos = { x = x, y = y, z = z } end
    end
    if not pos then
        local x, y, z = client.get_eye_pos()
        pos = { x = x, y = y - 40, z = z }
    end

    local px, py, pz = pos.x, pos.y, pos.z
    if ui.get_bool("Souls enabled") then spawn_souls(px, py, pz + 60) end
    if ui.get_bool("Cubes enabled") then spawn_cubes(px, py, pz + 60) end
    if ui.get_bool("Sparks enabled") then spawn_sparks(px, py, pz + 40) end
    out(string.format("[HTS debug] death att=%s victim=%s me=%s secret=%s pos=%s",
        tostring(attacker), tostring(victim), tostring(is_local(attacker)),
        tostring(secret_on()), tostring(px)))

    if is_local(attacker) and secret_on() then
        spawn_rocket(px, py, pz + 30)
    end

    if idx then last_hurt[idx] = nil end
end)

on("on_round_start", function()
    tracers = {}
    damage  = {}
    souls   = {}
    cubes   = {}
    sparks  = {}
    rockets = {}
    last_hurt = {}
    knife_stage = 0
    knife_holding = false
    knife_heavy_holding = false
    nimb_pos.x, nimb_pos.y, nimb_pos.z = nil, nil, nil
    mark_pos.x, mark_pos.y, mark_pos.z = nil, nil, nil
    rage.time = -100
    rage.valid = false
end)

on("on_antiaim", function(pitch, yaw)
    if type(yaw) == "number" then real_yaw = yaw end

    -- The native anti-aim writes the final view angles after the createmove
    -- callback, which is why setting cmd.viewangles alone was ignored while a
    -- knife target was in reach. Override the anti-aim output for those ticks
    -- and hand the angles back to the cheat as well.
    if knife_aim.on then
        pcall(cmd.viewangles, knife_aim.pitch, knife_aim.yaw)
        if antiaim then
            if antiaim.override_yaw then pcall(antiaim.override_yaw, knife_aim.yaw) end
            if antiaim.override_pitch then pcall(antiaim.override_pitch, knife_aim.pitch) end
        end
    elseif guard_aim.on then
        -- knife attacker rushing us: turn the body towards him, keep the camera
        if antiaim then
            if antiaim.override_yaw then pcall(antiaim.override_yaw, guard_aim.yaw) end
            if antiaim.override_pitch then pcall(antiaim.override_pitch, 0) end
        end
    end
end)

-- ============================== TICK ==============================

local IN_ATTACK = 1
local IN_ATTACK2 = 2048

local function zeus_target()
    local me = entity.get_local_player()
    if me == nil or not entity.is_alive(me) then return nil end

    local range = clamp(ui.get_int("Zeus range"), 10, 200)
    local range_sq = range * range
    local ox, oy, oz = client.get_eye_pos()

    local best, best_dist, bx, by, bz
    for _, idx in ipairs(get_players()) do
        if idx ~= me and entity.is_alive(idx) and entity.is_enemy(idx) then
            local ex, ey, ez = player_origin(idx)
            if ex then
                local dx, dy, dz = ox - ex, oy - ey, oz - (ez + 64)
                local d_sq = dx * dx + dy * dy + dz * dz
                if d_sq <= range_sq then
                    local hit = utils.trace_bullet(ox, oy, oz, ex, ey, ez + 64)
                    if hit then
                        local d = math.sqrt(d_sq)
                        if not best_dist or d < best_dist then
                            best, best_dist = idx, d
                            bx, by, bz = ex, ey, ez + 64
                        end
                    end
                end
            end
        end
    end
    return best, best_dist, bx, by, bz
end

-- The taser has no spread, so the only thing that decides a hit is how far the
-- view is from the enemy. Turn that angular error into a 0..100 hit chance.
local function zeus_hitchance(x, y, z)
    local ox, oy, oz = client.get_eye_pos()
    if not ox then return 100 end
    local vp, vy = cmd.viewangles()
    if type(vp) ~= "number" or type(vy) ~= "number" then return 100 end

    local dx, dy, dz = x - ox, y - oy, z - oz
    local flat = math.sqrt(dx * dx + dy * dy)
    if flat < 1 then return 100 end

    local want_yaw   = math.deg(atan2(dy, dx))
    local want_pitch = -math.deg(math.atan(dz / flat))
    local off_yaw    = math.abs((want_yaw - vy + 180) % 360 - 180)
    local off_pitch  = math.abs(want_pitch - vp)
    local off        = math.sqrt(off_yaw * off_yaw + off_pitch * off_pitch)

    -- angular half-size of the torso at this distance (~9 units)
    local body  = math.deg(math.atan(9 / flat))
    local inner = body * 0.25
    if off <= inner then return 100 end
    return floor(clamp(100 * (1 - (off - inner) / (body * 1.5)), 0, 100))
end

-- ============================== KNIFE BOT ==============================
-- CS2 melee reach is ~48 units from the player hull; 50 gives a small margin.
-- The bot only works while a knife is actually in hand, so it never fights with
-- the Zeus bot (taser) or the gun.
--
-- Combo: two fast light slashes (LMB), then one heavy slash (RMB), then a short
-- pause so the secondary attack is ready again. One swing cycle is ~0.4 s
-- (64 tick -> ~26 ticks), the secondary is ~1 s.

local KNIFE_RANGE = 50
local KNIFE_LIGHT_TICKS = 40   -- LMB is held this long -> two swings at most
local KNIFE_HEAVY_TICKS = 62   -- pause after RMB before the next combo

-- cmd.viewangles is overloaded in this build: calling it with no arguments
-- reads the angles, calling it with two arguments writes them. Passing a third
-- argument throws and the error is swallowed by pcall, which made the knife bot
-- stab wherever the player was looking. Try the call shapes in order and log
-- which one actually sticks.
local aim_style = 0       -- 0 unknown, 1 = (pitch, yaw), 2 = (pitch, yaw, 0), 3 = table
local aim_logged = false
local aim_lost_logged = false

local function aim_at(x, y, z)
    local ox, oy, oz = client.get_eye_pos()
    if not ox then return end
    local dx, dy, dz = x - ox, y - oy, z - oz
    local flat = math.sqrt(dx * dx + dy * dy)
    if flat < 1 then return end
    local yaw = math.deg(atan2(dy, dx))
    local pitch = -math.deg(math.atan(dz / flat))

    -- Did something (anti-aim / mouse input) overwrite the angles we set on the
    -- previous tick? One-shot log so it is obvious in the console.
    if knife_aim.on and not aim_lost_logged then
        local rp, ry = cmd.viewangles()
        if math.abs(rp - knife_aim.pitch) > 3 or math.abs(ry - knife_aim.yaw) > 3 then
            aim_lost_logged = true
            out(string.format("[HTS debug] aim lost: set=(%.1f,%.1f) now=(%s,%s)",
                knife_aim.pitch, knife_aim.yaw, tostring(rp), tostring(ry)))
        end
    end

    knife_aim.on = true
    knife_aim.pitch = pitch
    knife_aim.yaw = yaw

    local style, ok = aim_style, false

    if style == 0 or style == 1 then
        ok = pcall(cmd.viewangles, pitch, yaw)
        if ok then style = 1 end
    end
    if not ok and style ~= 3 then
        ok = pcall(cmd.viewangles, pitch, yaw, 0)
        if ok then style = 2 end
    end
    if not ok then
        ok = pcall(cmd.viewangles, { pitch, yaw, 0 })
        if ok then style = 3 end
    end
    aim_style = ok and style or 0

    -- The native anti-aim rewrites the final view angles after this callback, so
    -- cmd.viewangles alone is not enough while AA is on. Push the same angles
    -- through the anti-aim override as well so the sent angles point at the
    -- enemy, not where the camera happens to look.
    if antiaim then
        if antiaim.override_yaw then pcall(antiaim.override_yaw, yaw) end
        if antiaim.override_pitch then pcall(antiaim.override_pitch, pitch) end
    end

    if not aim_logged then
        aim_logged = true
        local rp, ry = cmd.viewangles()
        out(string.format(
            "[HTS debug] aim style=%d ok=%s set=(%.1f,%.1f) read=(%s,%s) target=(%.0f,%.0f,%.0f)",
            style, tostring(ok), pitch, yaw, tostring(rp), tostring(ry), x, y, z))
    end
end

local function knife_target()
    local me = entity.get_local_player()
    if me == nil or not entity.is_alive(me) then return nil end

    local ox, oy, oz = client.get_eye_pos()
    local px, py, pz = player_origin(me)
    if not ox or not px then return nil end

    local best, best_dist, bx, by, bz
    for _, idx in ipairs(get_players()) do
        if idx ~= me and entity.is_alive(idx) and entity.is_enemy(idx) then
            local ex, ey, ez = player_origin(idx)
            if ex then
                local dx, dy = ex - px, ey - py
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist <= KNIFE_RANGE and math.abs(ez - pz) < 72 then
                    -- head height; the view must really point at the enemy even
                    -- when he is not standing right in front of the camera
                    local tx, ty, tz = ex, ey, ez + 64
                    if not best_dist or dist < best_dist then
                        best, best_dist = idx, dist
                        bx, by, bz = tx, ty, tz
                    end
                end
            end
        end
    end
    return best, best_dist, bx, by, bz
end

-- ============================== NO SOUND JUMP ==============================
-- The landing is audible unless IN_DUCK is already in the landing usercmd.
-- Duck for the last few ticks of the fall plus a couple after touchdown, then
-- release immediately.

local function get_tick()
    local ok, v = pcall(cmd.tickcount)
    if ok and type(v) == "number" then return v end
    ok, v = pcall(client.get_tickcount)
    if ok and type(v) == "number" then return v end
    v = client.tickcount
    if type(v) == "number" then return v end
    return nil
end

local function player_eye(me)
    local ok, x, y, z = pcall(client.get_eye_pos)
    if ok and type(z) == "number" and not (x == 0 and y == 0 and z == 0) then
        return x, y, z
    end
    ok, x, y, z = pcall(entity.get_eye_pos, me)
    if ok and type(z) == "number" and not (x == 0 and y == 0 and z == 0) then
        return x, y, z
    end
    ok, x, y, z = pcall(entity.get_ent_origin, me)
    if ok and type(z) == "number" and not (x == 0 and y == 0 and z == 0) then
        return x, y, z
    end
    ok, x, y, z = pcall(entity.get_origin, me)
    if ok and type(z) == "number" and not (x == 0 and y == 0 and z == 0) then
        return x, y, z
    end
    return nil, nil, nil
end

local nsj = {
    z          = nil,
    dz         = 0,
    fall       = 0,
    duck_until = -1,
    forced     = false,
    diag_done  = false,
}

local function nsj_reset()
    nsj.z, nsj.dz, nsj.fall = nil, 0, 0
    nsj.duck_until, nsj.forced = -1, false
end

-- Is there solid ground within "dist" units below the eye?
-- trace_line does not see the world on this build (always clear), so the bullet
-- trace is used as a second opinion.
local function ground_ahead(x, y, z, dist)
    if utils.trace_line then
        local ok, frac = pcall(utils.trace_line, x, y, z, x, y, z - dist)
        if ok and type(frac) == "number" and frac < 0.995 then return true end
    end
    if utils.trace_bullet then
        local ok, hit = pcall(utils.trace_bullet, x, y, z, x, y, z - dist)
        if ok and hit then return true end
    end
    return false
end

local function no_sound_jump(me)
    if not ui.get_bool("No sound jump") or me == nil or not entity.is_alive(me) then
        if nsj.forced then pcall(cmd.buttons, IN_DUCK, 0) end
        nsj_reset()
        return
    end

    local tk = get_tick()
    if tk == nil then return end

    local x, y, z = player_eye(me)
    if z == nil then return end

    local dz = 0
    if nsj.z ~= nil then dz = z - nsj.z end

    if dz < -0.5 then
        nsj.fall = nsj.fall - dz
    elseif dz >= 0 then
        nsj.fall = 0
    end

    -- height stops dropping after a real fall: touchdown
    local land = nsj.dz < -0.5 and dz >= -0.5 and dz < 3.5 and nsj.fall > 30
    if land then
        nsj.duck_until = tk + 1
        nsj.fall = 0
        if not nsj.diag_done then
            nsj.diag_done = true
            local lf = 1
            if utils.trace_line then
                local ok, v = pcall(utils.trace_line, x, y, z, x, y, z - 100)
                if ok and type(v) == "number" then lf = v end
            end
            local bh = "nil"
            if utils.trace_bullet then
                local ok, v = pcall(utils.trace_bullet, x, y, z, x, y, z - 100)
                if ok then bh = tostring(v) end
            end
            out(string.format("[HTS] nsj line=%.3f bullet=%s", lf, bh))
        end
    elseif dz < -0.6 and nsj.fall > 6 then
        -- keep the crouch ~3-4 ticks before touchdown at any fall speed: a
        -- fixed distance would start far too early on a short, slow drop
        local lead = -dz * 4
        if lead < 16 then lead = 16 end
        if lead > 55 then lead = 55 end

        if ground_ahead(x, y, z, 64 + lead) then
            -- +2 tolerates one missed trace tick so a single bad sample does
            -- not drop IN_DUCK on the exact landing tick
            if tk + 2 > nsj.duck_until then nsj.duck_until = tk + 2 end
        end
    end

    nsj.z, nsj.dz = z, dz

    if tk <= nsj.duck_until then
        pcall(cmd.buttons, IN_DUCK, 1)
        nsj.forced = true

    elseif nsj.forced then
        pcall(cmd.buttons, IN_DUCK, 0)
        nsj.forced = false
    end
end

on("on_createmove", function()
    local now = client.curtime()


    local me  = entity.get_local_player()

    -- per-tick player origin cache (used by particles / death handling)
    for _, idx in ipairs(get_players()) do
        local x, y, z = player_origin(idx)
        if x then last_origin[idx] = { x = x, y = y, z = z } end
    end

    -- view angles are only readable inside on_createmove; cached for the camera anchor
    local p, y = cmd.viewangles()
    if type(p) == "number" then view_pitch = p end
    if type(y) == "number" then
        view_yaw = y
        real_yaw = y
    end

    -- ---- wasd keys -------------------------------------------------------
    update_wasd(me)

    -- ---- no sound jump ---------------------------------------------------
    no_sound_jump(me)

    -- ---- zeus ------------------------------------------------------------
    -- No auto-swap: shoot only when the taser is actually in hand, the target is in
    -- range and the current view is on him (Zeus hit chance).
    if ui.get_bool("Zeus bot") then
        local target, dist, bx, by, bz = zeus_target()
        local attack = false
        local hc_req = clamp(ui.get_int("Zeus hit chance"), 1, 100)

        if target then
            local me = entity.get_local_player()
            local is_taser = me and holds_taser(me)
            local ready    = me and zeus_ready(me)
            local hc       = zeus_hitchance(bx, by, bz)
            attack = (is_taser ~= false) and ready and hc >= hc_req

            if now - zeus_log_time >= 1.0 then
                zeus_log_time = now
                out(string.format(
                    "[HTS debug] zeus dist=%.0f hc=%d req=%d weapon=%s clip=%s taser=%s ready=%s attack=%s",
                    dist, hc, hc_req, tostring(weapon_name(me)), tostring(weapon_clip(me)),
                    tostring(is_taser), tostring(ready), tostring(attack)))
            end
        end

        if attack then
            cmd.buttons(IN_ATTACK, 1)
            zeus_holding = true
        elseif zeus_holding then
            cmd.buttons(IN_ATTACK, 0)
            zeus_holding = false
        end
    elseif zeus_holding then
        cmd.buttons(IN_ATTACK, 0)
        zeus_holding = false
    end

    -- ---- avoid backstab --------------------------------------------------
    -- A knife player running at us within 600 units: turn the body towards him
    -- so a backstab cannot land. The camera stays where the player aims.
    local guard_yaw = nil
    if ui.get_bool("Avoid backstab") and me and entity.is_alive(me) then
        local guard_range = clamp(ui.get_int("Backstab radius"), 100, 800)
        local px, py, pz = player_origin(me)
        if px then
            local best_d = nil
            for _, idx in ipairs(get_players()) do
                if idx ~= me and entity.is_alive(idx) and entity.is_enemy(idx)
                    and holds_knife(idx) then
                    local ex, ey, ez = player_origin(idx)
                    if ex then
                        local dx, dy = px - ex, py - ey
                        local d = math.sqrt(dx * dx + dy * dy)
                        if d <= guard_range and d > 1 and math.abs(pz - ez) < 200 then
                            local okv, vx, vy = pcall(entity.get_velocity, idx)
                            local toward = 0
                            if okv and type(vx) == "number" then
                                if type(vy) ~= "number" then vy = 0 end
                                toward = (vx * dx + vy * dy) / d
                            end
                            if toward > 30 and (best_d == nil or d < best_d) then
                                best_d = d
                                guard_yaw = math.deg(atan2(ey - py, ex - px))
                            end
                        end
                    end
                end
            end
        end
    end
    guard_aim.on = guard_yaw ~= nil
    if guard_yaw then guard_aim.yaw = guard_yaw end

    -- ---- knife bot -------------------------------------------------------
    -- Combo: hold LMB for two fast slashes, then one heavy RMB slash, then wait
    -- out the secondary cooldown and repeat. Only buttons the bot pressed are
    -- released, so the player's own right click (scope) is never blocked.
    if ui.get_bool("Knife bot") then
        local tick = get_tick()
        local has_knife = me and entity.is_alive(me) and holds_knife(me)
        local tgt, dist, bx, by, bz
        if has_knife then tgt, dist, bx, by, bz = knife_target() end

        if tgt and tick then
            -- keep the view glued to the enemy while he is in reach, including
            -- during the cooldown, so the next slash already starts aimed
            aim_at(bx, by, bz)

            if knife_stage == 0 then
                knife_stage = 1
                knife_stage_tick = tick
            end

            if knife_stage == 1 then
                cmd.buttons(IN_ATTACK, 1)
                knife_holding = true
                if tick - knife_stage_tick >= KNIFE_LIGHT_TICKS then
                    cmd.buttons(IN_ATTACK, 0)
                    knife_holding = false
                    knife_stage = 2
                    knife_stage_tick = tick
                end
            elseif knife_stage == 2 then
                cmd.buttons(IN_ATTACK2, 1)
                knife_heavy_holding = true
                knife_stage = 3
                knife_stage_tick = tick

                if now - knife_log_time >= 1.0 then
                    knife_log_time = now
                    local name = "?"
                    if entity.get_name then
                        local ok, n = pcall(entity.get_name, tgt)
                        if ok and n then name = tostring(n) end
                    end
                    out(string.format("[HTS debug] knife dist=%.0f target=%s weapon=%s aim=(%.1f,%.1f)",
                        dist, name, tostring(weapon_name(me)), knife_aim.pitch, knife_aim.yaw))
                end
            elseif knife_stage == 3 then
                if knife_heavy_holding then
                    cmd.buttons(IN_ATTACK2, 0)
                    knife_heavy_holding = false
                end
                if tick - knife_stage_tick >= KNIFE_HEAVY_TICKS then
                    knife_stage = 0
                end
            end
        else
            if knife_holding then
                cmd.buttons(IN_ATTACK, 0)
                knife_holding = false
            end
            if knife_heavy_holding then
                cmd.buttons(IN_ATTACK2, 0)
                knife_heavy_holding = false
            end
            knife_stage = 0
            knife_aim.on = false
        end
    else
        if knife_holding then
            cmd.buttons(IN_ATTACK, 0)
            knife_holding = false
        end
        if knife_heavy_holding then
            cmd.buttons(IN_ATTACK2, 0)
            knife_heavy_holding = false
        end
        knife_stage = 0
        knife_aim.on = false
    end

    -- ---- chat spam -------------------------------------------------------
    if ui.get_bool("Chat spam") then
        local delay = clamp(ui.get_float("Chat spam delay"), 1.0, 30.0)
        if now - spam_timer >= delay then
            spam_timer = now
            client.console_exec("say ★ hts.lua ★")
        end
    end
end)

out("[HTS] loaded ok")
out("[HTS] menu state: " .. tostring(menu_state_src))

-- one-shot API report: makes missing/renamed functions obvious in the console
out(string.format(
    "[HTS] api pawn=%s weapon_name=%s clip=%s set_bool=%s buttons=%s trace_bullet=%s move_type=%s prop=%s",
    tostring(entity.get_pawn_idx ~= nil),
    tostring(entity.get_weapon_name ~= nil),
    tostring(entity.get_weapon_clip ~= nil),
    tostring(ui.set_bool ~= nil),
    tostring(cmd.buttons ~= nil),
    tostring(utils.trace_bullet ~= nil),
    tostring(entity.get_move_type ~= nil),
    tostring(entity.get_prop ~= nil)))

-- one-shot module report: shows whether Double tap/tickbase can be driven from Lua
do
    local env = _ENV
    local cand = {
        "ragebot", "exploits", "exploit", "tickbase", "antiaim", "movement",
        "aimbot", "engine", "input", "config", "menu", "lagcomp", "hvh",
    }
    local found, tables = {}, {}

    for _, name in ipairs(cand) do
        local m = env and env[name]
        if m ~= nil then
            local keys = {}
            pcall(function()
                for k in pairs(m) do keys[#keys + 1] = tostring(k) end
            end)
            table.sort(keys)
            found[#found + 1] = name .. "={" .. table.concat(keys, ",") .. "}"
        end
    end

    pcall(function()
        for k, v in pairs(env) do
            if type(v) == "table" then tables[#tables + 1] = tostring(k) end
        end
    end)
    table.sort(tables)

    -- anything that smells like tickbase / double tap, wherever it lives
    local hits = {}
    pcall(function()
        for name, mod in pairs(env) do
            if type(mod) == "table" then
                for k in pairs(mod) do
                    local s = tostring(k):lower()
                    if s:find("double", 1, true) or s:find("tickbase", 1, true)
                        or s:find("exploit", 1, true) or s:find("shift", 1, true)
                        or s:find("tap", 1, true) then
                        hits[#hits + 1] = tostring(name) .. "." .. tostring(k)
                    end
                end
            end
        end
    end)
    table.sort(hits)

    out("[HTS] mods: " .. (#found > 0 and table.concat(found, " ") or "none"))
    out("[HTS] env tables: " .. table.concat(tables, ","))
    out("[HTS] dt hooks: " .. (#hits > 0 and table.concat(hits, ",") or "none"))
end


