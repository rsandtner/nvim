-- intellij-lsp's debug panel (<leader>dv) with its sections in the order
-- Watches, Locals, Call stack instead of the plugin's Call stack, Locals,
-- Watches. A test's call stack is ~80 JUnit frames, which push Locals and
-- Watches below the window; what you inspect at a breakpoint belongs on top.
--
-- The plugin has no option for the order, so this wraps its renderer
-- (`require('intellij-lsp.debug')._render`, which every redraw goes through):
-- the plugin draws as usual, then the three blocks are swapped in the buffer,
-- in `panel.rows` (what <CR>, <Tab>, dd and the frame preview look up by line)
-- and in the panel's highlights. The plugin itself stays untouched.
--
-- Relies on plugin internals (`_render`, its `panel` upvalue, the
-- 'intellij-lsp.debug.panel_row' namespace). If an update changes them, the
-- panel falls back to the plugin's own order instead of breaking.
local M = {}

local ORDER = { 'Watches', 'Locals', 'Call stack' }

--- Reorders the panel's sections.
--- @param lines string[] buffer lines as the plugin rendered them
--- @param rows table[] the plugin's row descriptors, one per line (`kind = 'header'` starts a section)
--- @param marks { row: integer }[] extmarks with a 0-based `row` (and `end_row`), remapped in place
--- @return string[]|nil lines, table[]|nil rows nil when the layout is not the expected one
function M.reorder(lines, rows, marks)
  if #lines ~= #rows then return nil end
  local start = {} -- section title -> 1-based header line
  local order = {} -- titles in rendered order
  for i, row in ipairs(rows) do
    if row.kind == 'header' then
      start[lines[i]] = i
      order[#order + 1] = lines[i]
    end
  end
  if #order ~= #ORDER then return nil end
  for _, title in ipairs(ORDER) do
    if not start[title] then return nil end
  end

  -- Each section runs from its header to the line before the next header,
  -- minus the blank separator line the plugin puts before every header.
  local range = {}
  for k, title in ipairs(order) do
    local first = start[title]
    local last = order[k + 1] and start[order[k + 1]] - 1 or #lines
    if order[k + 1] and rows[last] and rows[last].kind == 'blank' then last = last - 1 end
    range[title] = { first, last }
  end

  local new_lines, new_rows, new_index = {}, {}, {}
  local blank_row
  for k, title in ipairs(ORDER) do
    if k > 1 then
      new_lines[#new_lines + 1] = ''
      new_rows[#new_rows + 1] = blank_row or { kind = 'blank' }
    end
    local r = range[title]
    for i = r[1], r[2] do
      new_lines[#new_lines + 1] = lines[i]
      new_rows[#new_rows + 1] = rows[i]
      new_index[i] = #new_lines
    end
  end
  if #new_lines ~= #lines then return nil end

  for _, m in ipairs(marks) do
    local to = new_index[m.row + 1]
    if to then
      local span = (m.end_row or m.row) - m.row
      m.row = to - 1
      if m.end_row then m.end_row = m.row + span end
    end
  end
  return new_lines, new_rows
end

local function upvalue(fn, name)
  for i = 1, math.huge do
    local n, v = debug.getupvalue(fn, i)
    if not n then return nil end
    if n == name then return v end
  end
end

--- Swaps the sections of an already rendered panel. Errors are swallowed, so
--- the worst case is the plugin's own order.
local function apply(render)
  local panel = upvalue(render, 'panel')
  local ns = vim.api.nvim_get_namespaces()['intellij-lsp.debug.panel_row']
  if not (panel and ns and panel.rows and panel.root_buf) then return end
  local buf = panel.root_buf
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local marks = {}
  for _, e in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local d = e[4]
    marks[#marks + 1] = {
      row = e[2],
      col = e[3],
      end_row = d.end_row,
      end_col = d.end_col,
      hl_group = d.hl_group,
      line_hl_group = d.line_hl_group,
    }
  end

  local new_lines, new_rows = M.reorder(lines, panel.rows, marks)
  if not new_lines then return end

  panel.rows = new_rows
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, m.row, m.col, {
      end_row = m.end_row,
      end_col = m.end_col,
      hl_group = m.hl_group,
      line_hl_group = m.line_hl_group,
    })
  end
end

function M.setup()
  local ok, dbg = pcall(require, 'intellij-lsp.debug')
  if not ok or type(dbg._render) ~= 'function' or dbg._render_reordered then return end
  local render = dbg._render
  dbg._render = function(...)
    render(...)
    pcall(apply, render)
  end
  dbg._render_reordered = true
end

M.setup()

return M
