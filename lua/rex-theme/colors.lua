-- Neovim colorschemes built from Rex themes (`:colorscheme rex-<id>`).
-- Every color comes from the Rex theme: the interface from Rex's own interface
-- tokens, syntax from the theme's 16 terminal colors (what every program in Rex
-- uses). rex.lua reads the themes; they are cached in M.cache_file.
local M = {}

M.cache_file = vim.fn.stdpath("cache") .. "/rex-theme/themes.json"
M.colors_dir = vim.fn.stdpath("data") .. "/rex-theme" -- added to 'runtimepath'

local data

function M.themes()
  if not data then
    local f = io.open(M.cache_file, "r")
    local ok, t = pcall(vim.json.decode, f and f:read("*a") or "")
    if f then
      f:close()
    end
    data = ok and type(t) == "table" and t or {}
  end
  return data
end

-- (Re)write colors/rex-*.lua stubs so `:colorscheme` and pickers list every theme.
local function write_stubs()
  local dir = M.colors_dir .. "/colors"
  vim.fn.mkdir(dir, "p")
  local want = {}
  for id in pairs(data) do
    local file = ("%s/rex-%s.lua"):format(dir, id)
    want[file] = true
    if not vim.uv.fs_stat(file) then
      local f = assert(io.open(file, "w"))
      f:write(('require("rex-theme.colors").load(%q)\n'):format(id))
      f:close()
    end
  end
  for name in vim.fs.dir(dir) do
    if not want[dir .. "/" .. name] then
      os.remove(dir .. "/" .. name)
    end
  end
end

-- Store freshly read themes; returns true if they differ from the cache.
function M.update(themes)
  if vim.deep_equal(themes, M.themes()) and vim.uv.fs_stat(M.cache_file) then
    return false
  end
  data = themes
  vim.fn.mkdir(vim.fs.dirname(M.cache_file), "p")
  local f = assert(io.open(M.cache_file, "w"))
  f:write(vim.json.encode(themes))
  f:close()
  write_stubs()
  return true
end

function M.load(id)
  local theme = M.themes()[id]
  if not theme then
    error("Rex theme not found: " .. id .. " (run :RexTheme refresh)")
  end
  local c = theme.tokens
  local t = function(i)
    return c["tt-" .. i]
  end

  vim.cmd("highlight clear")
  vim.g.colors_name = "rex-" .. id
  vim.o.background = theme.appearance
  for i = 0, 15 do
    vim.g["terminal_color_" .. i] = t(i)
  end

  local bg, fg = c["term-bg"], c["tt-fg"]
  local muted, faint = c["text-secondary"], c["text-tertiary"]
  local hl = {
    -- editor
    Normal = { fg = fg, bg = bg },
    NormalNC = { link = "Normal" },
    NormalFloat = { fg = c.text, bg = c.raised },
    FloatBorder = { fg = c["border-strong"], bg = c.raised },
    FloatTitle = { fg = c.accent, bg = c.raised, bold = true },
    FloatFooter = { fg = muted, bg = c.raised },
    Cursor = { fg = bg, bg = c["tt-cursor"] },
    CursorLine = { bg = c.hover },
    CursorColumn = { link = "CursorLine" },
    ColorColumn = { bg = c.sidebar },
    CursorLineNr = { fg = c.accent, bold = true },
    LineNr = { fg = faint },
    SignColumn = { bg = bg },
    FoldColumn = { fg = faint, bg = bg },
    Folded = { fg = muted, bg = c.sidebar },
    EndOfBuffer = { fg = bg },
    NonText = { fg = c["border-strong"] },
    Whitespace = { fg = c.border },
    SpecialKey = { fg = c["border-strong"] },
    Conceal = { fg = faint },
    Visual = { bg = c["tt-selection"] },
    VisualNOS = { link = "Visual" },
    Search = { fg = c.warning, bg = c["warning-container"] },
    IncSearch = { fg = c["accent-on-solid"], bg = c["accent-solid"] },
    CurSearch = { link = "IncSearch" },
    Substitute = { link = "IncSearch" },
    MatchParen = { bg = c["accent-dim"], bold = true },
    WinSeparator = { fg = c.border },
    VertSplit = { link = "WinSeparator" },
    StatusLine = { fg = muted, bg = c.sidebar },
    StatusLineNC = { fg = faint, bg = c.sidebar },
    TabLine = { fg = faint, bg = c.sidebar },
    TabLineFill = { bg = c.sidebar },
    TabLineSel = { fg = c.text, bg = bg, bold = true },
    WinBar = { fg = muted },
    WinBarNC = { fg = faint },
    Pmenu = { fg = c.text, bg = c.raised },
    PmenuSel = { fg = c.text, bg = c["accent-container"], bold = true },
    PmenuSbar = { bg = c.raised },
    PmenuThumb = { bg = c["border-strong"] },
    PmenuKind = { fg = t(4), bg = c.raised },
    PmenuExtra = { fg = muted, bg = c.raised },
    WildMenu = { link = "PmenuSel" },
    QuickFixLine = { bg = c["accent-container"] },
    Directory = { fg = t(4) },
    Title = { fg = t(4), bold = true },
    ErrorMsg = { fg = c.danger },
    WarningMsg = { fg = c.warning },
    MoreMsg = { fg = c.success },
    Question = { fg = c.success },
    ModeMsg = { fg = c.text, bold = true },
    MsgArea = { fg = fg },
    SpellBad = { sp = c.danger, undercurl = true },
    SpellCap = { sp = c.warning, undercurl = true },
    SpellLocal = { sp = c.info, undercurl = true },
    SpellRare = { sp = t(5), undercurl = true },

    -- syntax (terminal colors)
    Comment = { fg = t(8), italic = true },
    Constant = { fg = t(9) },
    String = { fg = t(2) },
    Character = { fg = t(10) },
    Number = { link = "Constant" },
    Boolean = { link = "Constant" },
    Float = { link = "Constant" },
    Identifier = { fg = fg },
    Function = { fg = t(4) },
    Statement = { fg = t(5) },
    Keyword = { link = "Statement" },
    Conditional = { link = "Statement" },
    Repeat = { link = "Statement" },
    Label = { link = "Statement" },
    Exception = { link = "Statement" },
    Operator = { fg = muted },
    PreProc = { fg = t(13) },
    Include = { link = "PreProc" },
    Define = { link = "PreProc" },
    Macro = { link = "PreProc" },
    Type = { fg = t(3) },
    StorageClass = { link = "Type" },
    Structure = { link = "Type" },
    Typedef = { link = "Type" },
    Special = { fg = t(6) },
    SpecialChar = { link = "Special" },
    Tag = { fg = t(4) },
    Delimiter = { fg = muted },
    Debug = { fg = c.warning },
    Underlined = { underline = true },
    Error = { fg = c.danger },
    Todo = { fg = c["accent-on-solid"], bg = c["accent-solid"], bold = true },
    ["@variable"] = { fg = fg },
    ["@variable.builtin"] = { fg = t(1) },
    ["@variable.member"] = { fg = t(14) },
    ["@property"] = { fg = t(14) },
    ["@function.builtin"] = { fg = t(12) },
    ["@type.builtin"] = { fg = t(11) },
    ["@constructor"] = { fg = t(3) },
    ["@string.escape"] = { fg = t(6) },
    ["@string.regexp"] = { fg = t(6) },
    ["@punctuation"] = { fg = muted },
    ["@tag"] = { fg = t(4) },
    ["@tag.attribute"] = { fg = t(6) },
    ["@tag.delimiter"] = { fg = muted },
    ["@markup.heading"] = { fg = t(4), bold = true },
    ["@markup.link"] = { fg = t(6), underline = true },
    ["@markup.raw"] = { fg = t(2) },
    ["@markup.strong"] = { bold = true },
    ["@markup.italic"] = { italic = true },
    ["@markup.strikethrough"] = { strikethrough = true },
    ["@markup.quote"] = { fg = muted, italic = true },
    ["@markup.list"] = { fg = t(5) },

    -- diagnostics
    DiagnosticError = { fg = c.danger },
    DiagnosticWarn = { fg = c.warning },
    DiagnosticInfo = { fg = c.info },
    DiagnosticHint = { fg = t(6) },
    DiagnosticOk = { fg = c.success },
    DiagnosticVirtualTextError = { fg = c.danger, bg = c["danger-container"] },
    DiagnosticVirtualTextWarn = { fg = c.warning, bg = c["warning-container"] },
    DiagnosticVirtualTextInfo = { fg = c.info, bg = c["info-container"] },
    DiagnosticVirtualTextHint = { fg = t(6), bg = c.sidebar },
    DiagnosticUnderlineError = { sp = c.danger, undercurl = true },
    DiagnosticUnderlineWarn = { sp = c.warning, undercurl = true },
    DiagnosticUnderlineInfo = { sp = c.info, undercurl = true },
    DiagnosticUnderlineHint = { sp = t(6), undercurl = true },
    DiagnosticUnnecessary = { fg = faint },
    LspReferenceText = { bg = c.selected },
    LspReferenceRead = { bg = c.selected },
    LspReferenceWrite = { bg = c.selected, underline = true },
    LspInlayHint = { fg = faint, bg = c.sidebar },
    LspSignatureActiveParameter = { fg = c.accent, bold = true },

    -- diff and git
    DiffAdd = { bg = c["success-container"] },
    DiffChange = { bg = c["info-container"] },
    DiffDelete = { fg = c.danger, bg = c["danger-container"] },
    DiffText = { bg = c["accent-dim"] },
    Added = { fg = c.success },
    Changed = { fg = c.warning },
    Removed = { fg = c.danger },
    GitSignsAdd = { fg = c.success },
    GitSignsChange = { fg = c.warning },
    GitSignsDelete = { fg = c.danger },

    -- plugins (most link to the groups above already)
    SnacksIndent = { fg = c.border },
    SnacksIndentScope = { fg = faint },
    SnacksPickerMatch = { fg = c.accent, bold = true },
    SnacksDashboardHeader = { fg = c.accent },
    WhichKey = { fg = c.accent },
    WhichKeyGroup = { fg = t(4) },
    WhichKeyDesc = { fg = fg },
    WhichKeySeparator = { fg = faint },
    BlinkCmpMenuBorder = { link = "FloatBorder" },
    BlinkCmpLabelMatch = { fg = c.accent, bold = true },
    FlashLabel = { fg = c["accent-on-solid"], bg = c["accent-solid"], bold = true },
    FlashMatch = { link = "Search" },
    FlashBackdrop = { fg = faint },
  }
  for group, spec in pairs(hl) do
    vim.api.nvim_set_hl(0, group, spec)
  end
end

return M
