-- The Rex side: read Rex's themes and selected themes from its preferences,
-- select themes and import new ones through the `rex` CLI.
local M = {}

M.domain = "com.superlogical.rex"
M.aliases = {} -- Rex theme name -> nvim colorscheme (setup's `aliases`)

local TOKENS = "Contents/Resources/SuperUI_SuperDesignTokens.bundle/Contents/Resources/themes.json"

---------------------------------------------------------------------------
-- Processes: inside M.async() they don't block the editor, elsewhere they wait.
---------------------------------------------------------------------------
local function exec(cmd)
  local co, main = coroutine.running()
  if not co or main then
    return vim.system(cmd, { text = true }):wait()
  end
  vim.system(cmd, { text = true }, function(r)
    vim.schedule(function()
      coroutine.resume(co, r)
    end)
  end)
  return coroutine.yield()
end

-- Run fn in a coroutine; on_done(err) gets nil on success.
function M.async(fn, on_done)
  coroutine.wrap(function()
    local ok, err = pcall(fn)
    if on_done then
      on_done(not ok and err or nil)
    end
  end)()
end

---------------------------------------------------------------------------
-- Rex data
---------------------------------------------------------------------------
local function xml_unescape(s)
  return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

-- Reads straight from cfprefsd: the plist on disk lags behind by seconds.
local function prefs()
  local r = exec({ "defaults", "export", M.domain, "-" })
  local xml = r.code == 0 and r.stdout or ""
  local function value(key)
    local kind, v = xml:match("<key>" .. vim.pesc(key) .. "</key>%s*<(%a+)>(.-)</%a+>")
    if kind == "data" then
      local ok, s = pcall(vim.base64.decode, (v:gsub("%s", "")))
      return ok and s or nil
    end
    return v and xml_unescape(v)
  end
  local ok, customs = pcall(vim.json.decode, value("Workspace.customThemes") or "")
  return {
    dark = value("Workspace.darkThemeID"),
    light = value("Workspace.lightThemeID"),
    customs = ok and type(customs) == "table" and customs or {},
  }
end

local builtin_file -- false when Rex isn't installed
local function builtin_themes()
  if builtin_file == nil then
    builtin_file = false
    local r = exec({ "mdfind", ("kMDItemCFBundleIdentifier == '%s'"):format(M.domain) })
    local apps = vim.split(r.stdout or "", "\n", { trimempty = true })
    vim.list_extend(apps, vim.fn.glob("/Applications/Rex*.app", false, true))
    for _, app in ipairs(apps) do
      if vim.uv.fs_stat(app .. "/" .. TOKENS) then
        builtin_file = app .. "/" .. TOKENS
        break
      end
    end
  end
  local f = builtin_file and io.open(builtin_file, "r")
  if not f then
    return {}
  end
  local ok, list = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and type(list) == "table" and list or {}
end

local function slug(name)
  return (name:lower():gsub("[^a-z0-9]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

-- "NAME (nvim)" / "NAME (nvim dark|light)" -> NAME: themes exported from nvim.
local function exported_name(name)
  return name:match("^(.*) %(nvim%)$") or name:match("^(.*) %(nvim dark%)$") or name:match("^(.*) %(nvim light%)$")
end

local function ours(name)
  return exported_name(name) ~= nil or M.aliases[name] ~= nil
end

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------
local function hex(r, g, b)
  local function c(v)
    return math.max(0, math.min(255, math.floor(v + 0.5)))
  end
  return ("#%02x%02x%02x"):format(c(r), c(g), c(b))
end

local function unhex(h)
  return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16)
end

-- t of color a over color b.
local function mix(a, b, t)
  local ar, ag, ab = unhex(a)
  local br, bg, bb = unhex(b)
  return hex(ar * t + br * (1 - t), ag * t + bg * (1 - t), ab * t + bb * (1 - t))
end

local function p3_to_srgb(r, g, b)
  local function lin(c)
    return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
  end
  local function enc(c)
    c = math.max(0, math.min(1, c))
    return (c <= 0.0031308 and 12.92 * c or 1.055 * c ^ (1 / 2.4) - 0.055) * 255
  end
  r, g, b = lin(r), lin(g), lin(b)
  return enc(1.2249 * r - 0.2247 * g), enc(-0.0420 * r + 1.0419 * g), enc(-0.0197 * r - 0.0786 * g + 1.0979 * b)
end

local function color_dict(c)
  if (c.colorSpace or "srgb") ~= "srgb" then
    return hex(p3_to_srgb(c.red, c.green, c.blue))
  end
  return hex(c.red * 255, c.green * 255, c.blue * 255)
end

-- Rex CSS variable ("#rrggbb", "r g b", "rgb(r g b / a)") -> hex; translucent
-- colors are blended over base.
local function css_color(value, base)
  local v = vim.trim(value)
  if v:sub(1, 1) == "#" then
    return v:lower()
  end
  v = v:gsub("^rgb%(", ""):gsub("%)$", "")
  local r, g, b, a = v:match("^%s*([%d.]+)%s+([%d.]+)%s+([%d.]+)%s*/?%s*([%d.]*)%s*$")
  if not r then
    return nil
  end
  local h = hex(tonumber(r), tonumber(g), tonumber(b))
  return (a ~= "" and base) and mix(h, base, tonumber(a)) or h
end

local function builtin_tokens(t)
  local css = {}
  for k, v in pairs(t.cssVariables) do
    css[k:gsub("^%-%-super%-", "")] = v
  end
  local base = css_color(css.bg, nil)
  local out = {}
  for k, v in pairs(css) do
    out[k] = css_color(v, base)
  end
  return out
end

-- Imported themes carry only terminal colors: derive the interface tokens.
local function custom_tokens(t)
  local p = t.palette
  local bg, fg = color_dict(p.background), color_dict(p.foreground)
  local cursor = p.cursor and color_dict(p.cursor) or fg
  local tk = {
    bg = bg,
    ["term-bg"] = bg,
    pane = bg,
    text = fg,
    ["tt-fg"] = fg,
    ["tt-cursor"] = cursor,
    ["tt-selection"] = p.selectionBackground and color_dict(p.selectionBackground) or mix(fg, bg, 0.2),
    sidebar = mix(fg, bg, 0.04),
    raised = mix(fg, bg, 0.08),
    border = mix(fg, bg, 0.15),
    ["border-strong"] = mix(fg, bg, 0.25),
    hover = mix(fg, bg, 0.05),
    selected = mix(fg, bg, 0.08),
    ["text-secondary"] = mix(fg, bg, 0.6),
    ["text-tertiary"] = mix(fg, bg, 0.45),
    accent = cursor,
    ["accent-solid"] = cursor,
    ["accent-on-solid"] = bg,
    ["accent-container"] = mix(cursor, bg, 0.18),
    ["accent-dim"] = mix(cursor, bg, 0.23),
  }
  for i, c in ipairs(p.ansi) do
    tk["tt-" .. (i - 1)] = color_dict(c)
  end
  for i, name in ipairs({ "danger", "success", "warning", "info" }) do
    tk[name] = tk["tt-" .. i]
    tk[name .. "-container"] = mix(tk["tt-" .. i], bg, 0.15)
  end
  return tk
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

-- Every Rex theme except the ones exported from nvim, keyed by id:
-- { name, appearance, tokens = { [token] = "#rrggbb" } }.
function M.themes()
  local themes = {}
  for _, t in ipairs(prefs().customs) do
    if not ours(t.name) then
      themes[slug(t.name)] = { name = t.name, appearance = t.appearance, tokens = custom_tokens(t) }
    end
  end
  for _, t in ipairs(builtin_themes()) do -- built-ins win on id clashes
    themes[t.id] = { name = t.name, appearance = t.appearance, tokens = builtin_tokens(t) }
  end
  return themes
end

-- Rex's selected themes as nvim colorscheme names:
-- { dark = { name = ..., alias = bool }, light = ... } (a slot may be nil).
function M.state()
  local p = prefs()
  local by_id = {}
  for _, t in ipairs(p.customs) do
    by_id[t.id] = t
  end
  local state = {}
  for _, slot in ipairs({ "dark", "light" }) do
    local id = p[slot]
    local t = id and by_id[id]
    if t and M.aliases[t.name] then
      state[slot] = { name = M.aliases[t.name], alias = true }
    elseif t then
      state[slot] = { name = exported_name(t.name) or ("rex-" .. slug(t.name)) }
    elseif id and id ~= "" then
      state[slot] = { name = "rex-" .. id }
    end
  end
  return state
end

local function rex(...)
  local r = exec({ "rex", "do", ... })
  if r.code ~= 0 then
    error(vim.trim(r.stderr ~= "" and r.stderr or r.stdout), 0)
  end
end

-- Select colorscheme `name` for `slot` in Rex. `rex-<id>` selects that Rex
-- theme; any other name is imported from `ghostty` (theme file text) on first
-- use as "NAME (nvim)", or "NAME (nvim light)" when "NAME (nvim)" is dark.
function M.select(slot, name, ghostty)
  local customs = prefs().customs
  local value
  local id = name:match("^rex%-(.+)$")
  if id then
    value = id -- built-ins are selected by id, imported themes by name
    for _, t in ipairs(customs) do
      if slug(t.name) == id and not ours(t.name) then
        value = t.name
      end
    end
  else
    local by_name = {}
    for _, t in ipairs(customs) do
      by_name[t.name] = t
    end
    local plain, specific = name .. " (nvim)", ("%s (nvim %s)"):format(name, slot)
    for _, candidate in ipairs({ plain, specific }) do
      if not value and by_name[candidate] and by_name[candidate].appearance == slot then
        value = candidate
      end
    end
    if not value then
      value = by_name[plain] and specific or plain
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      local file = dir .. "/" .. value -- Rex names the theme after the file
      local f = assert(io.open(file, "w"))
      f:write(ghostty)
      f:close()
      local ok, err = pcall(rex, "client.theme.import", "path=" .. file)
      vim.fn.delete(dir, "rf")
      if not ok then
        error(err, 0)
      end
    end
  end
  rex(("client.setting.themes.%s.palette"):format(slot), "value=" .. value)
end

-- Path of Rex's built-in theme file, or nil (for :checkhealth).
function M.app_themes_file()
  builtin_themes()
  return builtin_file or nil
end

return M
