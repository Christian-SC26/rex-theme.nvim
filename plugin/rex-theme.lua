local actions = {
  pick = function()
    require("rex-theme").pick()
  end,
  transparent = function()
    require("rex-theme").toggle_transparent()
  end,
  refresh = function()
    require("rex-theme").refresh()
  end,
}

vim.api.nvim_create_user_command("RexTheme", function(o)
  local action = actions[o.args ~= "" and o.args or "pick"]
  if not action then
    return vim.notify("RexTheme: unknown action " .. o.args, vim.log.levels.ERROR)
  end
  action()
end, {
  nargs = "?",
  desc = "rex-theme: pick | transparent | refresh",
  complete = function()
    return vim.tbl_keys(actions)
  end,
})
