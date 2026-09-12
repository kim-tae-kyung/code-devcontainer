-- Optional built-in plugin: https://neovim.io/doc/user/plugins/#difftool
vim.cmd.packadd('nvim.difftool')

-- Git's temporary comparison trees are for review, not project analysis.
-- The -d option is already set before init.lua runs.
if vim.o.diff then
  return
end

-- Reuse the language servers installed for Claude Code; no plugin manager.
-- https://neovim.io/doc/user/lsp/#lsp-quickstart
vim.lsp.config('gopls', {
  cmd = { 'gopls' },
  filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
  root_markers = { 'go.work', 'go.mod', '.git' },
})

vim.lsp.config('pyright', {
  cmd = { 'pyright-langserver', '--stdio' },
  filetypes = { 'python' },
  root_markers = {
    'pyrightconfig.json',
    { 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', 'Pipfile' },
    '.git',
  },
})

vim.lsp.config('ts_ls', {
  cmd = { 'typescript-language-server', '--stdio' },
  filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' },
  root_markers = { { 'tsconfig.json', 'jsconfig.json', 'package.json' }, '.git' },
  init_options = { hostInfo = 'neovim' },
})

vim.lsp.config('rust_analyzer', {
  cmd = { 'rust-analyzer' },
  filetypes = { 'rust' },
  root_dir = function(bufnr, on_dir)
    local crate = vim.fs.root(bufnr, 'Cargo.toml')
    if not crate then
      on_dir(vim.fs.root(bufnr, { 'rust-project.json', '.git' }))
      return
    end
    -- Cargo identifies the workspace when this file belongs to a member crate.
    -- Keep root discovery offline and avoid changing the project's lockfile.
    vim.system({
      'cargo', 'metadata', '--no-deps', '--format-version', '1',
      '--offline', '--locked', '--manifest-path', crate .. '/Cargo.toml',
    }, { text = true }, function(result)
      vim.schedule(function()
        local ok, metadata = pcall(vim.json.decode, result.stdout or '')
        on_dir(result.code == 0 and ok and metadata.workspace_root or crate)
      end)
    end)
  end,
})

-- Native completion on server trigger characters; explicitly accept with C-y.
-- https://neovim.io/doc/user/lsp/#lsp-completion
vim.opt.completeopt:append({ 'menuone', 'noselect' })
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if client and client:supports_method('textDocument/completion') then
      vim.lsp.completion.enable(true, client.id, event.buf, { autotrigger = true })
    end
  end,
})

vim.lsp.enable({ 'gopls', 'pyright', 'ts_ls', 'rust_analyzer' })
