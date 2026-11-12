-- IntelliJ's code lenses (Run | Debug on a main method, Run Test | Debug Test
-- on test classes and methods) at the end of a line, instead of Neovim's own
-- rendering: a virtual line of its own above the declaration, which pushes the
-- code apart and sits between the annotation and the method.
--
--   @Test  Run Test | Debug Test
--   void addsTwoNumbers() {
--
-- Placement: the nearest test annotation above the declaration (any
-- `@…Test`, plus @TestFactory/@TestTemplate: @Test, @ParameterizedTest,
-- @SpringBootTest, ...); a declaration without one (a main method, a plain
-- test class) gets the lens at the end of its own line.
--
-- The built-in display (vim.lsp.codelens) is switched off for IntelliJ
-- buffers and this module fetches the lenses itself: on attach, on entering
-- the buffer, after edits (debounced), when the server asks for a refresh and
-- when its progress (import, indexing) ends.
--
-- <leader>rl (run the lens on this line) is replaced so it works on both the
-- annotation line and the declaration line. <leader>rt / <leader>dt are the
-- plugin's and pick the test around the cursor on their own.
local NAME = 'intellij'
local ns = vim.api.nvim_create_namespace('features.jvm.lens')

--- Per buffer: client id, and lenses by row (both the row they are drawn on
--- and the row the server put them on).
--- @type table<integer, { client_id: integer, rows: table<integer, lsp.CodeLens[]> }>
local state = {}
local timers = {}
local hooked = {}

local function is_test_annotation(line)
  local name = line:match('^%s*@([%w_.]+)')
  name = name and name:match('([%w_]+)$')
  return name ~= nil and (name:match('Test$') ~= nil or name == 'TestFactory' or name == 'TestTemplate')
end

-- Walks up the annotation block above `row` (the declaration's name line) to a
-- test annotation. Stops at a blank line or anything that ends a statement,
-- block or comment, so it never wanders into the previous member.
local function anchor_row(buf, row)
  local first = math.max(0, row - 15)
  local lines = vim.api.nvim_buf_get_lines(buf, first, row + 1, false)
  for r = row, first, -1 do
    local line = lines[r - first + 1] or ''
    if is_test_annotation(line) then
      return r
    end
    if r < row then
      local annotation = line:find('@', 1, true) ~= nil
      if line:match('^%s*$') or (not annotation and (line:match('[;{}]%s*$') or line:match('%*/%s*$'))) then
        break
      end
    end
  end
  return row
end

local function render(buf, client_id, lenses)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local drawn, rows = {}, {}
  local function add(t, row, lens)
    t[row] = t[row] or {}
    table.insert(t[row], lens)
  end
  -- By position, then in the server's order: Run and Debug share a range, and
  -- table.sort is not stable, so without the tie-break they swap at random.
  local index = {}
  for i, lens in ipairs(lenses) do
    index[lens] = i
  end
  table.sort(lenses, function(a, b)
    if a.range.start.line ~= b.range.start.line then
      return a.range.start.line < b.range.start.line
    end
    if a.range.start.character ~= b.range.start.character then
      return a.range.start.character < b.range.start.character
    end
    return index[a] < index[b]
  end)
  for _, lens in ipairs(lenses) do
    if lens.command and (lens.command.title or '') ~= '' then
      local row = lens.range.start.line
      local anchor = anchor_row(buf, row)
      add(drawn, anchor, lens)
      add(rows, anchor, lens)
      if anchor ~= row then
        add(rows, row, lens)
      end
    end
  end
  for row, list in pairs(drawn) do
    local chunks = { { ' ', 'LspCodeLensSeparator' } }
    for i, lens in ipairs(list) do
      if i > 1 then
        chunks[#chunks + 1] = { ' | ', 'LspCodeLensSeparator' }
      end
      chunks[#chunks + 1] = { lens.command.title, 'LspCodeLens' }
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
      virt_text = chunks,
      virt_text_pos = 'eol',
      hl_mode = 'combine',
    })
  end
  state[buf] = { client_id = client_id, rows = rows }
end

local function refresh(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local client = vim.lsp.get_clients({ bufnr = buf, name = NAME })[1]
  if not client then
    return
  end
  local tick = vim.b[buf].changedtick
  local params = { textDocument = vim.lsp.util.make_text_document_params(buf) }
  client:request('textDocument/codeLens', params, function(err, result)
    vim.schedule(function()
      -- An edit since the request: its rows are stale, the next refresh is coming.
      if err or not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].changedtick ~= tick then
        return
      end
      render(buf, client.id, result or {})
    end)
  end, buf)
end

local function refresh_later(buf, delay)
  local timer = timers[buf]
  if not timer then
    timer = vim.uv.new_timer()
    timers[buf] = timer
  end
  timer:stop()
  timer:start(delay, 0, vim.schedule_wrap(function()
    refresh(buf)
  end))
end

local function refresh_client(client)
  for buf in pairs(client.attached_buffers) do
    refresh_later(buf, 100)
  end
end

-- The server sends workspace/codeLens/refresh when lenses change without an
-- edit here (import done, a test added in another file). Chained in front of
-- whatever handler is installed already.
local function hook_refresh(client)
  if hooked[client.id] then
    return
  end
  hooked[client.id] = true
  local method = 'workspace/codeLens/refresh'
  local previous = client.handlers[method] or vim.lsp.handlers[method]
  client.handlers[method] = function(err, result, ctx, config)
    refresh_client(client)
    if previous then
      return previous(err, result, ctx, config)
    end
    return vim.NIL
  end
end

local function run_on_line()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local s = state[buf]
  local list = s and s.rows[row]
  local client = s and vim.lsp.get_client_by_id(s.client_id)
  if not (list and client) then
    return vim.notify('No code lens on this line', vim.log.levels.INFO)
  end
  local function exec(lens)
    client:exec_cmd(lens.command, { bufnr = buf })
  end
  if #list == 1 then
    return exec(list[1])
  end
  vim.ui.select(list, {
    prompt = 'Code lens',
    format_item = function(lens) return lens.command.title end,
  }, function(lens)
    if lens then
      exec(lens)
    end
  end)
end

local group = vim.api.nvim_create_augroup('features.jvm.lens', { clear = true })

vim.api.nvim_create_autocmd('LspAttach', {
  group = group,
  desc = 'IntelliJ: code lenses at the end of the annotation line',
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client or client.name ~= NAME then
      return
    end
    local buf = ev.buf
    -- Scheduled: LspAttach fires before the client's on_attach, where
    -- intellij-lsp enables the built-in lenses and maps <leader>rl.
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      pcall(vim.lsp.codelens.enable, false, { bufnr = buf, client_id = client.id })
      hook_refresh(client)
      vim.keymap.set('n', '<leader>rl', run_on_line, {
        buffer = buf,
        desc = 'Run the code lens on this line (IntelliJ)',
      })
      refresh(buf)
    end)
    vim.api.nvim_create_autocmd({ 'BufEnter', 'InsertLeave' }, {
      group = group,
      buffer = buf,
      callback = function() refresh_later(buf, 50) end,
    })
    vim.api.nvim_create_autocmd('TextChanged', {
      group = group,
      buffer = buf,
      callback = function() refresh_later(buf, 300) end,
    })
  end,
})

vim.api.nvim_create_autocmd('LspProgress', {
  group = group,
  pattern = 'end',
  desc = 'IntelliJ: refresh code lenses after import/indexing',
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client.name == NAME then
      refresh_client(client)
    end
  end,
})

vim.api.nvim_create_autocmd({ 'LspDetach', 'BufWipeout' }, {
  group = group,
  callback = function(ev)
    if ev.event == 'LspDetach' then
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if not client or client.name ~= NAME then
        return
      end
    end
    local timer = timers[ev.buf]
    if timer then
      timer:stop()
      timer:close()
      timers[ev.buf] = nil
    end
    state[ev.buf] = nil
    pcall(vim.api.nvim_buf_clear_namespace, ev.buf, ns, 0, -1)
  end,
})
