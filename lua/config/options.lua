local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.signcolumn = 'yes'

-- System clipboard; scheduled because the provider lookup slows startup.
vim.schedule(function()
  opt.clipboard = 'unnamedplus'
end)

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.inccommand = 'split'

-- Indentation defaults (4 spaces); filetypes override where their convention differs.
opt.expandtab = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftround = true
opt.breakindent = true

-- Persistent undo
opt.undofile = true

-- Windows and scrolling
opt.splitright = true
opt.splitbelow = true
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = false

-- Whitespace display
opt.list = true
opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Behaviour
opt.confirm = true
opt.updatetime = 250
opt.mouse = 'a'
