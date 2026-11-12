-- Catppuccin following the macOS appearance: Mocha when dark, Latte when light.
-- Icons come from mini.icons and need a Nerd Font in the terminal (see Brewfile).
vim.pack.add({
  { src = 'https://github.com/catppuccin/nvim', name = 'catppuccin' },
  'https://github.com/nvim-mini/mini.icons',
})

require('catppuccin').setup({
  -- 'auto' picks the flavour from 'background', so flipping 'background'
  -- reloads the colorscheme in the matching flavour.
  flavour = 'auto',
  background = { light = 'latte', dark = 'mocha' },
})

require('mini.icons').setup()
-- Plugins that only know nvim-web-devicons get mini.icons through this shim.
MiniIcons.mock_nvim_web_devicons()

-- Neovim sets 'background' from the terminal's OSC 11 reply and re-queries on
-- DEC mode 2031 theme notifications. Rex answers neither OSC 11 nor surfaces
-- the notification, so macOS itself is the source of truth here.
if vim.fn.has('mac') == 1 then
  local query = { 'defaults', 'read', '-g', 'AppleInterfaceStyle' }

  -- The key exists only in dark mode; light mode makes `defaults` exit non-zero.
  local function appearance(result)
    return result.code == 0 and result.stdout:match('Dark') and 'dark' or 'light'
  end

  local function apply(background)
    if vim.o.background ~= background then
      vim.o.background = background
    end
  end

  local function sync()
    vim.system(query, { text = true }, function(result)
      vim.schedule(function()
        apply(appearance(result))
      end)
    end)
  end

  apply(appearance(vim.system(query, { text = true }):wait()))

  -- Toggling the appearance from Control Center does not always move focus away
  -- from the terminal, so poll in addition to re-checking on focus.
  vim.uv.new_timer():start(3000, 3000, sync)
  vim.api.nvim_create_autocmd('FocusGained', {
    group = vim.api.nvim_create_augroup('features.theme', { clear = true }),
    desc = 'Follow the macOS appearance',
    callback = sync,
  })
end

vim.cmd.colorscheme('catppuccin')
