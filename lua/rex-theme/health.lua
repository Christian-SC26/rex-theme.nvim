local M = {}

function M.check()
  local h = vim.health
  h.start("rex-theme.nvim")
  if vim.fn.has("mac") == 0 then
    h.warn("Not macOS: Rex sync and system appearance are off; slots still work")
    return
  end
  local file = require("rex-theme.rex").app_themes_file()
  if file then
    h.ok("Rex found: " .. file:gsub("/Contents/Resources/.*", ""))
  else
    h.warn("Rex.app not found: no rex-* themes")
  end
  local n = vim.tbl_count(require("rex-theme.colors").themes())
  h.info(("%d Rex themes available as rex-*"):format(n))
  if vim.fn.executable("rex") == 1 then
    h.ok("`rex` CLI on PATH")
    h.info("Changing Rex themes needs Remote Control on (Rex Settings > Rex Server)")
  else
    h.warn("`rex` CLI not on PATH: changes in nvim won't reach Rex")
  end
end

return M
