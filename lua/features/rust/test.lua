-- Run and test Rust with the JVM keys (features/jvm/intellij.lua), on top of
-- rustaceanvim (features/rust/lsp.lua). Every run goes through rust-analyzer's
-- runnables and rustaceanvim's `rust-analyzer.runSingle` command, the same
-- path as a click on a Run lens, so `:RustLsp! runnables` / `testables` rerun
-- whatever a key or a lens started.
--
-- Rust buffers, set on attach below:
--   <leader>rt          run the test at the cursor, else its test module,
--                       else every test of the crate (cargo test --all-targets)
--   <leader>rT          run the last test run again; nothing run yet: pick one
--   <leader>rr          run the binary (`fn main` at the cursor, else the
--                       crate's binaries; a picker if there are several)
--   <leader>rR          the same, asking for its arguments first
--   <leader>rl          run the code lens on this line (features/lens.lua)
-- Tests run in the background (no terminal): passed → a notification with
-- cargo's summary (and our quickfix window closes); failed → the quickfix
-- window opens at the bottom, one entry per failed test on the line that
-- panicked (the assert), compile errors on their `-->` line. The cursor stays
-- where it is (a run may end mid-typing): <C-w>j to go there, ]q / :cc to jump
-- straight to the failure, q or <Esc> in the window closes it.
-- Binaries run in a terminal split (rustaceanvim's `termopen`), so a TUI works;
-- <Esc> in normal mode closes it.
--
-- Lenses: Run/Debug only, at the end of the `#[test]` line (the attribute,
-- not the `fn` line rust-analyzer puts them on), `fn main` and `mod tests` on
-- their own line. rust-analyzer's "N implementations" lenses are switched off.
local NAME = 'rust-analyzer'

local M = {}

--- @param path string
--- @param root string
local function absolute(path, root)
  if path:sub(1, 1) == '/' then
    return path
  end
  return vim.fs.joinpath(root, path)
end

-- A test's panic, old and new format:
--   thread 'a::b' panicked at src/x.rs:3:5:          (Rust 1.73+)
--   thread 'a::b' (4376616) panicked at src/x.rs:3:5: (with thread id)
-- followed by the message up to a blank line, a `note:` line or cargo's
-- closing `error: test failed, ...`.
local PANIC = "^thread '([^']+)'[^']-panicked at (.-):(%d+):(%d+):%s*$"
-- A compile error: `error[E0308]: mismatched types`, then `  --> src/x.rs:3:5`.
local ERROR = '^error%[?[%w]*%]?: (.*)$'
local ARROW = '^%s*%-%->%s*(.-):(%d+):(%d+)%s*$'

--- Quickfix items for cargo's output: failed tests (on the line that panicked)
--- and compile errors. Continuation lines of a panic message (assert_eq!'s
--- `left:` / `right:`) follow their entry as text-only lines.
--- @param output string stdout and stderr of `cargo test`
--- @param root string directory cargo ran in; relative paths are resolved against it
--- @return vim.quickfix.entry[]
function M.quickfix_items(output, root)
  local lines = vim.split(output:gsub('\r\n', '\n'), '\n', { plain = true })
  local items = {}
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local test, file, lnum, col = line:match(PANIC)
    local headline = not test and line:match(ERROR)
    if test then
      local message = {}
      i = i + 1
      while i <= #lines and lines[i] ~= '' and not lines[i]:match('^note: ') and not lines[i]:match('^error')
        and not lines[i]:match(PANIC) do
        message[#message + 1] = lines[i]
        i = i + 1
      end
      items[#items + 1] = {
        filename = absolute(file, root),
        lnum = tonumber(lnum),
        col = tonumber(col),
        text = test .. ': ' .. (message[1] or 'panicked'),
        type = 'E',
      }
      for k = 2, #message do
        items[#items + 1] = { text = message[k], valid = false }
      end
    elseif headline and lines[i + 1] and lines[i + 1]:match(ARROW) then
      local efile, elnum, ecol = lines[i + 1]:match(ARROW)
      items[#items + 1] = {
        filename = absolute(efile, root),
        lnum = tonumber(elnum),
        col = tonumber(ecol),
        text = line,
        type = 'E',
      }
      i = i + 2
    else
      i = i + 1
    end
  end
  return items
end

local QF_TITLE = 'cargo test'

-- rustaceanvim test executor: runs cargo without a terminal and reports
-- through notifications and quickfix.
--- @type rustaceanvim.Executor
local quickfix_executor = {
  execute_command = function(command, args, cwd, opts)
    opts = opts or {}
    cwd = cwd or vim.fn.getcwd()
    -- The test filter: the first argument after `--` that is not a flag.
    local name = 'all tests'
    local after = vim.fn.index(args, '--')
    if after >= 0 and args[after + 2] and not vim.startswith(args[after + 2], '-') then
      name = args[after + 2]
    end
    vim.notify('Testing ' .. name .. ' …', vim.log.levels.INFO)
    local cmd = vim.list_extend({ command }, args)
    vim.system(cmd, { cwd = cwd, env = opts.env, text = true }, function(done)
      vim.schedule(function()
        local output = (done.stderr or '') .. '\n' .. (done.stdout or '')
        local summary = (done.stdout or ''):match('test result: [^\n]*')
        local title = QF_TITLE .. ' ' .. name
        if done.code == 0 then
          -- Drop our stale failures, never someone else's list (a grep).
          if vim.startswith(vim.fn.getqflist({ title = 0 }).title, QF_TITLE) then
            vim.fn.setqflist({}, 'r', { title = title, items = {} })
            vim.cmd.cclose()
          end
          return vim.notify(summary or (name .. ' passed'), vim.log.levels.INFO)
        end
        local items = M.quickfix_items(output, cwd)
        if #items == 0 then
          -- Nothing recognised (a crash, a timeout): the raw output, unparsed.
          vim.fn.setqflist({}, ' ', { title = title, lines = vim.split(output, '\n'), efm = '%m' })
        else
          vim.fn.setqflist({}, ' ', { title = title, items = items })
        end
        -- Open, but leave the cursor where it was.
        local win = vim.api.nvim_get_current_win()
        vim.cmd('botright copen')
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_current_win(win)
        end
        vim.notify(summary or (name .. ' failed'), vim.log.levels.ERROR)
      end)
    end)
  end,
}

-- Plugin options are read once, when rustaceanvim's config first loads (the
-- first Rust buffer); a function keeps options other modules set.
local previous = vim.g.rustaceanvim
vim.g.rustaceanvim = function()
  local base = type(previous) == 'function' and previous() or previous or {}
  return vim.tbl_deep_extend('force', base, {
    tools = { test_executor = quickfix_executor, crate_test_executor = quickfix_executor },
  })
end

vim.lsp.config(NAME, {
  settings = { ['rust-analyzer'] = { lens = { implementations = { enable = false } } } },
})

require('features.lens').register(NAME, {
  label = 'rust-analyzer',
  -- #[test], #[tokio::test], #[rstest], #[test_case(..)], #[test_log::test]
  is_anchor = function(line)
    local path = line:match('^%s*#%[%s*([%w_:]+)')
    local last = path and path:match('([%w_]+)$')
    return last ~= nil and (last:match('^test') ~= nil or last:match('test$') ~= nil)
  end,
  is_annotation = function(line) return line:find('#[', 1, true) ~= nil end,
})

--- @param runnable table rust-analyzer runnable
local function cargo_command(runnable)
  return runnable.args and runnable.args.cargoArgs and runnable.args.cargoArgs[1]
end

--- Size of the runnable's range in lines; nil without one (crate-wide).
local function span(runnable, row)
  local range = runnable.location and runnable.location.targetRange
  if not range or range.start.line > row or range['end'].line < row then
    return nil
  end
  return range['end'].line - range.start.line
end

--- Calls `fn(client, runnables)` with the buffer's runnables.
local function with_runnables(buf, fn)
  local client = vim.lsp.get_clients({ bufnr = buf, name = NAME })[1]
  if not client then
    return vim.notify('rust-analyzer is not attached', vim.log.levels.WARN)
  end
  local params = { textDocument = vim.lsp.util.make_text_document_params(buf) }
  client:request('experimental/runnables', params, function(err, result)
    if err then
      return vim.notify('rust-analyzer: ' .. err.message, vim.log.levels.ERROR)
    end
    vim.schedule(function() fn(client, result or {}) end)
  end, buf)
end

local function exec(client, buf, runnable)
  client:exec_cmd({ title = runnable.label, command = 'rust-analyzer.runSingle', arguments = { runnable } }, { bufnr = buf })
end

--- The innermost runnable around `row` among `list`, else the first without a
--- range (the crate-wide one).
local function innermost(list, row)
  local best, best_span, fallback
  for _, r in ipairs(list) do
    local s = span(r, row)
    if s and (not best_span or s < best_span) then
      best, best_span = r, s
    elseif not r.location and not fallback then
      fallback = r
    end
  end
  return best or fallback
end

local function test_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  with_runnables(buf, function(client, runnables)
    local tests = vim.tbl_filter(function(r) return cargo_command(r) == 'test' end, runnables)
    local runnable = innermost(tests, row)
    if not runnable then
      return vim.notify('No test here', vim.log.levels.INFO)
    end
    exec(client, buf, runnable)
  end)
end

local last_args = ''

local function run_binary(ask)
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  with_runnables(buf, function(client, runnables)
    local bins = vim.tbl_filter(function(r) return cargo_command(r) == 'run' end, runnables)
    local function go(runnable)
      if not runnable then
        return
      end
      if not ask then
        return exec(client, buf, runnable)
      end
      vim.ui.input({ prompt = runnable.label .. ' -- ', default = last_args }, function(input)
        if not input then
          return
        end
        last_args = input
        local with_args = vim.deepcopy(runnable)
        with_args.args.executableArgs = vim.split(input, '%s+', { trimempty = true })
        exec(client, buf, with_args)
      end)
    end
    local here = vim.iter(bins):find(function(r) return span(r, row) ~= nil end)
    if here or #bins == 1 then
      return go(here or bins[1])
    end
    if #bins == 0 then
      return vim.notify('No binary to run', vim.log.levels.INFO)
    end
    vim.ui.select(bins, { prompt = 'Run', format_item = function(r) return r.label end }, go)
  end)
end

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('features.rust.test', { clear = true }),
  desc = 'Run and test keys for rust-analyzer',
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client or client.name ~= NAME then
      return
    end
    local function map(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    map('<leader>rt', test_at_cursor, 'Run the test at the cursor, else its module, else the crate')
    map('<leader>rT', function() vim.cmd.RustLsp({ 'testables', bang = true }) end, 'Run the last test again')
    map('<leader>rr', function() run_binary(false) end, 'Run the binary')
    map('<leader>rR', function() run_binary(true) end, 'Run the binary with arguments')
  end,
})

return M
