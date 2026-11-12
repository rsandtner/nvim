-- Treesitter: syntax highlighting and indentation from parsers.
-- Uses the nvim-treesitter `main` branch, which only installs parsers and
-- queries; highlighting and indentation are started per buffer below.
-- Parsers are compiled locally and need the `tree-sitter` CLI (see Brewfile).

local parsers = {
  'java', 'kotlin', 'groovy', 'xml', 'properties',
  'go', 'rust',
  'lua', 'vim', 'vimdoc', 'query',
  'markdown', 'markdown_inline',
  'json', 'yaml', 'toml', 'bash',
}

-- Rebuild parsers after the plugin updates, so they match the new queries.
-- Must be registered before vim.pack.add() so it also fires on first install.
vim.api.nvim_create_autocmd('PackChanged', {
  group = vim.api.nvim_create_augroup('features.treesitter.update', { clear = true }),
  desc = 'Update treesitter parsers after nvim-treesitter changes',
  callback = function(ev)
    local data = ev.data
    if data.spec.name == 'nvim-treesitter' and data.kind == 'update' then
      if not data.active then
        vim.cmd.packadd('nvim-treesitter')
      end
      vim.cmd('TSUpdate')
    end
  end,
})

vim.pack.add({
  { src = 'https://github.com/nvim-treesitter/nvim-treesitter', version = 'main' },
})

-- Installs only what is missing; runs asynchronously, so startup is not blocked.
require('nvim-treesitter').install(parsers)

-- Neovim names the filetype `jproperties`; the parser is `properties`.
vim.treesitter.language.register('properties', 'jproperties')

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('features.treesitter', { clear = true }),
  desc = 'Start treesitter highlighting and indentation',
  callback = function(ev)
    -- Fails quietly for filetypes without an installed parser.
    if not pcall(vim.treesitter.start, ev.buf) then
      return
    end
    -- Only where nvim-treesitter has an indent query (Kotlin, for one, has
    -- none); otherwise keep the filetype's own indent script.
    local lang = vim.treesitter.language.get_lang(vim.bo[ev.buf].filetype)
    if lang and vim.treesitter.query.get(lang, 'indents') then
      vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})
