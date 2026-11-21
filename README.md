# rex-theme.nvim

Keep Neovim and Rex (the terminal by Superlogical) on the same color theme, in both directions, with separate dark and light themes.

- **Every Rex theme in Neovim.** All built-in and imported Rex themes become colorschemes named `rex-<id>` (`:colorscheme rex-static-noir`). The editor UI uses the theme's own interface colors from Rex, and syntax uses its 16 terminal colors.
- **Every Neovim theme in Rex.** When you pick a colorscheme, it is exported from its live highlight colors and imported into Rex as `<name> (nvim)`. You don't need Ghostty or any other theme file.
- **Separate dark and light slots, like Rex.** Picking a theme shows it right away and saves it to the slot of its own appearance. The macOS appearance decides which slot you see. A change made in Rex shows up in Neovim within about a second.
- **Live preview picker.** Browsing doesn't save or sync anything, and <kbd>Esc</kbd> restores the theme you had.
- **Transparent background** (on by default inside Rex), so the editor background is exactly the one Rex draws.

This is an unofficial plugin. It reads Rex's preferences and controls Rex through the `rex` CLI.

## Requirements

- macOS with Rex installed. On other systems the slots and the picker still work, but there is no sync and no `rex-*` themes.
- Neovim 0.10+.
- The `rex` CLI on `PATH`, with **Remote Control** turned on in Rex Settings > Rex Server. Neovim needs this to change Rex's theme.
- Optional: [snacks.nvim](https://github.com/folke/snacks.nvim) for the live preview picker. Without it, `vim.ui.select` is used.

## Install

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "Christian-SC26/rex-theme.nvim",
  lazy = false,
  priority = 1000,
  opts = {},
  keys = {
    { "<leader>uC", function() require("rex-theme").pick() end, desc = "Colorscheme (rex-theme)" },
    { "<leader>uB", function() require("rex-theme").toggle_transparent() end, desc = "Transparent background" },
  },
}
```

The plugin picks the colorscheme itself, so turn off any other colorscheme setup. With LazyVim:

```lua
{ "LazyVim/LazyVim", opts = { colorscheme = function() end } },
```

Colorscheme plugins you want to choose from can stay `lazy = true`; lazy.nvim loads them on `:colorscheme`.

## Usage

| | |
|---|---|
| `:RexTheme` / `:RexTheme pick` | Colorscheme picker with live preview |
| `:RexTheme transparent` | Toggle the transparent background |
| `:RexTheme refresh` | Re-read Rex's themes (this also runs on every start) |
| `:colorscheme <name>` | Works too: the theme is stored and synced like a pick |
| `:checkhealth rex-theme` | Check the setup |

When Neovim starts, Rex's current dark and light themes win. After that, whichever side changes last wins.

## Configuration

These are the defaults:

```lua
opts = {
  -- Colorschemes for an empty slot, or one whose theme fails to load.
  fallback = { dark = "default", light = "default" },
  -- Clear the editor background. nil: on when running inside Rex.
  transparent = nil,
  -- Show the dark or light slot following the macOS appearance.
  follow_system = true,
  -- Two-way sync of the selected themes with Rex.
  sync = true,
  -- How often to check the macOS appearance and Rex's selection, in ms.
  interval = 1500,
  -- Rex themes that are really copies of nvim themes (e.g. imported from
  -- Ghostty): { ["Rex theme name"] = "nvim colorscheme" }. They are hidden
  -- from the rex-* list and replaced in Rex by an exact export when shown.
  aliases = {},
  -- Highlight groups whose background is cleared when transparent.
  transparent_groups = { "Normal", "NormalNC", "SignColumn", "EndOfBuffer", "LineNr", "FoldColumn" },
}
```

With `follow_system = true`, you don't need a separate dark mode plugin.

## Limitations

- Rex has no API to delete or overwrite an imported theme. If a Neovim theme's colors change, for example after a plugin update, delete its `(nvim)` copy in Rex. The next pick imports it again.
- A theme that exists in only one appearance is exported under its own name. If you export the same colorscheme name in both appearances (for example `everforest` with `background=dark` and `background=light`), the second copy is named `<name> (nvim light)`.

## How it works

- **Reading Rex.** Rex's built-in themes come from `themes.json` in the app bundle. Imported themes and the current selection come from `defaults export com.superlogical.rex`.
- **Changing Rex.** Neovim calls `rex do client.theme.import` and `rex do client.setting.themes.<dark|light>.palette`.
- **Watching for changes.** Every `interval` ms, one `defaults read` checks the macOS appearance and Rex's selected theme IDs.
- **Exporting a Neovim theme.** The export uses `Normal`, `Cursor`, `Visual` and `terminal_color_0..15`. Themes without terminal colors get them from their diagnostic and syntax colors.

## License

MIT
