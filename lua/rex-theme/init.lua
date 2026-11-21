-- rex-theme.nvim: dark/light theme slots for Neovim, kept in sync with Rex.
--
--  * Two independent slots, like Rex: a dark theme and a light theme. Picking a
--    theme shows it at once and stores it in the slot of its own appearance;
--    the macOS appearance decides which slot is shown.
--  * Rex themes are available as `rex-<id>` colorschemes (colors.lua).
--  * nvim themes are exported to Rex from their own colors as "<name> (nvim)".
--  * Optional transparent background, so the background is exactly Rex's.
local colors = require("rex-theme.colors")
local rex = require("rex-theme.rex")

local M = {}

---@class RexTheme.Config
local defaults = {
  -- Colorschemes for a slot that is empty or whose theme fails to load.
  fallback = { dark = "default", light = "default" },
  -- Clear the editor background. nil: on when running inside Rex.
  transparent = nil, ---@type boolean?
  -- Show the dark or light slot following the macOS appearance.
  follow_system = true,
  -- Two-way sync of the selected themes with Rex (needs the `rex` CLI).
  sync = true,
  -- How often to check the macOS appearance and Rex's selection, in ms.
  interval = 1500,
  -- Rex themes that are really copies of nvim themes (e.g. imported from
  -- Ghostty): { ["Rex theme name"] = "nvim colorscheme" }. They are hidden from
  -- the rex-* list and replaced in Rex by an exact export when shown.
  aliases = {},
  -- Highlight groups whose background is cleared when transparent.
  transparent_groups = { "Normal", "NormalNC", "SignColumn", "EndOfBuffer", "LineNr", "FoldColumn" },
}

M.config = vim.deepcopy(defaults)
M.mode = nil -- shown slot: "dark" | "light"
M.current = nil -- colorscheme as invoked (themes often set a bare colors_name)
M.slots = {} -- { dark = name, light = name }
M.previewing = false -- a picker is previewing: don't store or sync
local falling_back = false -- showing the fallback: keep the slot's own theme

local slots_file = vim.fn.stdpath("state") .. "/rex-theme.json"
local is_mac = vim.fn.has("mac") == 1 and vim.fn.executable("defaults") == 1

local function read_slots()
  local f = io.open(slots_file, "r")
  if not f then
    return {}
  end
  local ok, s = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and type(s) == "table" and s or {}
end

local function save_slots()
  local f = io.open(slots_file, "w")
  if f then
    f:write(vim.json.encode(M.slots))
    f:close()
  end
end

local function system_mode()
  if not is_mac then
    return vim.o.background
  end
  local out = vim.system({ "defaults", "read", "-g", "AppleInterfaceStyle" }, { text = true }):wait().stdout
  return (out or ""):find("Dark") and "dark" or "light"
end

-- Show the theme of `mode`'s slot.
function M.apply(mode)
  M.mode = mode
  local name = M.slots[mode] or M.config.fallback[mode]
  if M.current == name and vim.o.background == mode then
    return
  end
  vim.g.colors_name = nil -- so setting 'background' doesn't reload the old scheme
  vim.o.background = mode -- themes like everforest pick their variant from it
  if not pcall(vim.cmd.colorscheme, name) then
    falling_back = true
    pcall(vim.cmd.colorscheme, M.config.fallback[mode])
    falling_back = false
  end
end

---------------------------------------------------------------------------
-- Transparent background
---------------------------------------------------------------------------
local function apply_transparency()
  if not M.transparent then
    return
  end
  for _, group in ipairs(M.config.transparent_groups) do
    local h = vim.api.nvim_get_hl(0, { name = group, link = false })
    h.bg, h.ctermbg = nil, nil
    vim.api.nvim_set_hl(0, group, h)
  end
end

function M.toggle_transparent()
  M.transparent = not M.transparent
  if M.current then
    vim.cmd.colorscheme(M.current)
  end
  vim.notify("Transparent background " .. (M.transparent and "on" or "off"))
end

---------------------------------------------------------------------------
-- Export an nvim theme as a Ghostty theme file for Rex
---------------------------------------------------------------------------
local function hl_color(group, attr)
  local v = vim.api.nvim_get_hl(0, { name = group, link = false })[attr]
  return v and ("#%06x"):format(v)
end

-- Ghostty-format text of the current colors. Must run before transparency.
local function export_text()
  local dark = vim.o.background == "dark"
  local bg = hl_color("Normal", "bg") or (dark and "#000000" or "#ffffff")
  local fg = hl_color("Normal", "fg") or (dark and "#ffffff" or "#000000")
  local p = {}
  for i = 0, 15 do
    p[i] = vim.g["terminal_color_" .. i]
  end
  if not p[1] then -- theme sets no terminal colors: use its syntax colors
    local surface = hl_color("CursorLine", "bg") or hl_color("Pmenu", "bg") or bg
    local acc = {
      hl_color("DiagnosticError", "fg"),
      hl_color("String", "fg"),
      hl_color("DiagnosticWarn", "fg"),
      hl_color("Function", "fg"),
      hl_color("Statement", "fg"),
      hl_color("Special", "fg") or hl_color("DiagnosticHint", "fg"),
    }
    p[0], p[7] = dark and surface or fg, dark and fg or surface
    p[8], p[15] = hl_color("Comment", "fg") or fg, dark and fg or bg
    for i = 1, 6 do
      p[i], p[i + 8] = acc[i] or fg, acc[i] or fg
    end
  end
  local lines = {}
  for i = 0, 15 do
    lines[#lines + 1] = ("palette = %d=%s"):format(i, p[i])
  end
  vim.list_extend(lines, {
    "background = " .. bg,
    "foreground = " .. fg,
    "cursor-color = " .. (hl_color("Cursor", "bg") or fg),
    "cursor-text = " .. bg,
    "selection-background = " .. (hl_color("Visual", "bg") or fg),
    "selection-foreground = " .. (hl_color("Visual", "fg") or fg),
  })
  return table.concat(lines, "\n") .. "\n"
end

---------------------------------------------------------------------------
-- Rex sync
---------------------------------------------------------------------------
local rex_state = nil -- Rex's selection (rex.state()); nil until first read
local quiet_until = 0 -- ignore Rex changes we caused ourselves
local snapshots = {} -- "name|appearance" -> Ghostty text
local warned = false
local can_sync = false

local function warn(err)
  if err and not warned then
    warned = true
    vim.notify(
      ("rex-theme: %s\nIs Remote Control on? (Rex Settings > Rex Server)"):format(err),
      vim.log.levels.WARN
    )
  end
end

local function push(slot, name)
  if not can_sync or not rex_state then
    return -- wait for the first read: at startup Rex's selection wins
  end
  local cur = rex_state[slot]
  if cur and not cur.alias and cur.name == name then
    return
  end
  local text = snapshots[name .. "|" .. slot]
  if not name:match("^rex%-") and not text then
    return
  end
  rex_state[slot] = { name = name }
  quiet_until = vim.uv.now() + 5000
  rex.async(function()
    rex.select(slot, name, text)
  end, function(err)
    quiet_until = vim.uv.now() + 1000
    warn(err)
  end)
end

-- Re-read Rex's themes; returns true if anything changed. Waits for the
-- result unless called inside rex.async().
local function refresh()
  return colors.update(rex.themes())
end

local function pull()
  if vim.uv.now() < quiet_until then
    return
  end
  rex.async(function()
    local s = rex.state()
    if vim.uv.now() < quiet_until then
      return
    end
    local prev = rex_state
    rex_state = s
    local changed = false
    for _, slot in ipairs({ "dark", "light" }) do
      local ref = s[slot]
      local was = prev and prev[slot]
      if ref and (not was or was.name ~= ref.name) and M.slots[slot] ~= ref.name then
        local id = ref.name:match("^rex%-(.+)$")
        if id and not colors.themes()[id] then
          refresh() -- imported into Rex since the last read
        end
        M.slots[slot], changed = ref.name, true
      end
    end
    if changed then
      save_slots()
      M.apply(M.mode)
    end
    -- Replace an alias (an inexact copy) in Rex with the exact export.
    local shown = s[vim.o.background]
    if shown and shown.alias and M.current == shown.name then
      push(vim.o.background, M.current)
    end
  end, warn)
end

local timer
local function start_polling()
  if timer then
    timer:stop()
  end
  local follow, sync = M.config.follow_system, can_sync
  if not is_mac or not (follow or sync) then
    return
  end
  local script = "defaults read -g AppleInterfaceStyle 2>/dev/null; echo '|'"
  if sync then
    script = script
      .. (" ; defaults read %s Workspace.darkThemeID; defaults read %s Workspace.lightThemeID"):format(
        rex.domain,
        rex.domain
      )
  end
  local last_ids
  timer = vim.uv.new_timer()
  timer:start(0, M.config.interval, function()
    vim.system({ "sh", "-c", script }, { text = true }, function(r)
      local appearance, ids = (r.stdout or ""):match("^(.-)|(.*)$")
      if not appearance then
        return
      end
      local mode = appearance:find("Dark") and "dark" or "light"
      vim.schedule(function()
        if follow and mode ~= M.mode then
          M.apply(mode)
        end
      end)
      -- During our own push, leave last_ids alone so a change made in Rex
      -- meanwhile is still noticed once the quiet window ends.
      if sync and ids ~= last_ids and vim.uv.now() >= quiet_until then
        last_ids = ids
        vim.schedule(pull)
      end
    end)
  end)
end

---------------------------------------------------------------------------
-- Picker
---------------------------------------------------------------------------

-- Colorscheme picker with live preview; only the confirmed theme is stored.
function M.pick()
  local ok, Snacks = pcall(require, "snacks")
  if not ok or not Snacks.picker then
    vim.ui.select(vim.fn.getcompletion("", "color"), { prompt = "Colorscheme" }, function(name)
      if name then
        vim.cmd.colorscheme(name)
      end
    end)
    return
  end
  M.previewing = true
  Snacks.picker.colorschemes({
    on_close = function()
      vim.defer_fn(function()
        M.previewing = false
      end, 300) -- after the picker restores the previous theme
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        picker.preview.state.colorscheme = nil -- don't restore the old one
        vim.schedule(function()
          M.previewing = false
          vim.cmd.colorscheme(item.text)
        end)
      end
    end,
  })
end

function M.refresh()
  rex.async(function()
    local changed = refresh()
    vim.notify(("rex-theme: %d Rex themes%s"):format(
      vim.tbl_count(colors.themes()),
      changed and " (updated)" or ""
    ))
  end, warn)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

-- "dark" | "light" from the luminance of Normal's background, nil if unset.
local function appearance_of_normal()
  local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  if not bg then
    return nil
  end
  local r, g, b = math.floor(bg / 65536) % 256, math.floor(bg / 256) % 256, bg % 256
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) < 128 and "dark" or "light"
end

local retrying = false

local function on_colorscheme(ev)
  -- Dark-only themes that don't set 'background' come out broken when loaded
  -- under 'background=light' and vice versa: reload once with the other value
  -- if the result doesn't match. Scheduled, because :colorscheme is a silent
  -- no-op while another one is still loading.
  local seen = appearance_of_normal()
  if not retrying and seen and seen ~= vim.o.background then
    vim.schedule(function()
      retrying = true
      vim.g.colors_name = nil
      vim.o.background = seen
      pcall(vim.cmd.colorscheme, ev.match)
      retrying = false
    end)
    return
  end
  local name, appearance = ev.match, vim.o.background
  if can_sync and not name:match("^rex%-") then
    snapshots[name .. "|" .. appearance] = export_text()
  end
  apply_transparency()
  if M.previewing or falling_back then
    return
  end
  M.current = name
  if M.slots[appearance] ~= name then
    M.slots[appearance] = name
    save_slots()
  end
  push(appearance, name)
end

---@param opts? RexTheme.Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  if M.config.transparent == nil then
    M.transparent = vim.env.REX_SESSION ~= nil
  else
    M.transparent = M.config.transparent
  end
  rex.aliases = M.config.aliases
  M.slots = read_slots()
  can_sync = is_mac and M.config.sync and vim.fn.executable("rex") == 1

  vim.opt.rtp:prepend(colors.colors_dir)
  if is_mac and not vim.uv.fs_stat(colors.cache_file) then
    pcall(refresh) -- first run: list Rex's themes right away
  end

  local group = vim.api.nvim_create_augroup("rex_theme", { clear = true })
  vim.api.nvim_create_autocmd("ColorSchemePre", {
    group = group,
    callback = function()
      for i = 0, 15 do -- so a theme without terminal colors doesn't inherit stale ones
        vim.g["terminal_color_" .. i] = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = on_colorscheme })

  M.apply(M.config.follow_system and system_mode() or vim.o.background)
  start_polling()
  if is_mac then
    rex.async(refresh) -- pick up Rex updates and newly imported themes
  end
end

return M
