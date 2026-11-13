-- Rust through rust-analyzer, started by rustaceanvim: navigation (also into
-- std and crate sources), references, rename, code actions, clippy
-- diagnostics, completion (blink.cmp, features/completion.lua) and rustfmt.
-- rust-analyzer itself is the rustup component from the global mise config
-- (`rust = { components = [..., "rust-analyzer"] }`), found on PATH.
--
-- rustaceanvim is a filetype plugin: no setup() call, the client (named
-- `rust-analyzer`) starts when the first Rust buffer opens. Never also call
-- vim.lsp.enable('rust_analyzer'): that would start a second client next to it.
--
-- Configuration goes in two places, both set at startup:
--   vim.lsp.config('rust-analyzer', { settings = { ['rust-analyzer'] = ... } })
--                  server settings; rustaceanvim merges them over its defaults
--   vim.g.rustaceanvim
--                  plugin options (test executor, debug adapter)
-- Neither is needed yet: rustaceanvim runs clippy as the check command already
-- (check = clippy --no-deps, on save) whenever cargo-clippy is on PATH and no
-- `check` setting is given.
--
-- Ours, in Rust buffers:
--   inlay hints     on from the start (types, parameter names, chaining)
--   <leader>ch      toggle inlay hints in every Rust buffer
--   on save         format with rustfmt (through rust-analyzer); Rust only
-- Server-agnostic LSP maps (gd, K, <leader>ca/cf, <leader>s*) live in
-- features/lsp.lua. Rust-only extras are commands, unmapped:
--   :RustLsp expandMacro / openDocs / parentModule / explainError / crateGraph
--   :RustLsp codeAction (grouped) / hover actions
vim.pack.add({
  { src = 'https://github.com/mrcjkb/rustaceanvim', version = vim.version.range('^9') },
})

local NAME = 'rust-analyzer'

-- Shared by every Rust buffer, so a buffer opened after the toggle follows it.
local hints_on = true

local function rust_buffers()
  local bufs = {}
  for _, client in ipairs(vim.lsp.get_clients({ name = NAME })) do
    for buf in pairs(client.attached_buffers) do
      bufs[#bufs + 1] = buf
    end
  end
  return bufs
end

local function toggle_hints()
  hints_on = not hints_on
  -- Per buffer: enable() without a bufnr would switch the hints of every
  -- server (intellij-lsp too) and of buffers opened later.
  for _, buf in ipairs(rust_buffers()) do
    vim.lsp.inlay_hint.enable(hints_on, { bufnr = buf })
  end
  vim.notify('Inlay hints ' .. (hints_on and 'on' or 'off'), vim.log.levels.INFO)
end

local group = vim.api.nvim_create_augroup('features.rust.lsp', { clear = true })

vim.api.nvim_create_autocmd('LspAttach', {
  group = group,
  desc = 'Inlay hints, toggle key and format on save for rust-analyzer',
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client or client.name ~= NAME then
      return
    end
    local buf = ev.buf

    vim.lsp.inlay_hint.enable(hints_on, { bufnr = buf })
    vim.keymap.set('n', '<leader>ch', toggle_hints, { buffer = buf, desc = 'Toggle inlay hints' })

    -- Synchronous, so the write waits for rustfmt's edits. A crate whose code
    -- does not parse is written unformatted; rust-analyzer reports why.
    vim.api.nvim_clear_autocmds({ group = group, event = 'BufWritePre', buffer = buf })
    vim.api.nvim_create_autocmd('BufWritePre', {
      group = group,
      buffer = buf,
      desc = 'Format with rustfmt before writing',
      callback = function()
        vim.lsp.buf.format({ bufnr = buf, id = client.id, timeout_ms = 3000 })
      end,
    })
  end,
})
