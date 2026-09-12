#!/usr/bin/env python3
"""Exercise the image's real Neovim LSP clients and git-ndiff integration."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


LUA_DRIVER = r'''
local spec = vim.json.decode(vim.env.NVIM_SMOKE_SPEC)

local function check_lsp()
  local buf = vim.api.nvim_get_current_buf()
  local client
  assert(vim.wait(60000, function()
    client = vim.lsp.get_clients({ bufnr = buf, name = spec.server })[1]
    return client and client.initialized
  end, 100), 'LSP did not attach: ' .. spec.server)
  assert(client.config.root_dir == spec.root, 'Wrong workspace root: ' .. tostring(client.config.root_dir))

  local definition
  assert(vim.wait(60000, function()
    local reply = client:request_sync('textDocument/definition', {
      textDocument = { uri = vim.uri_from_bufnr(buf) },
      position = { line = spec.line, character = spec.character },
    }, 2000, buf)
    definition = reply and not reply.err and reply.result
    return type(definition) == 'table' and next(definition) ~= nil
  end, 200), 'No definition response from ' .. spec.server)

  assert(vim.wait(60000, function()
    local reply = client:request_sync('textDocument/completion', {
      textDocument = { uri = vim.uri_from_bufnr(buf) },
      position = { line = spec.line, character = spec.character + 3 },
      context = { triggerKind = 1 },
    }, 2000, buf)
    local result = reply and not reply.err and reply.result
    if type(result) ~= 'table' then return false end
    for _, item in ipairs(result.items or result) do
      if item.label:find('answer', 1, true) then return true end
    end
    return false
  end, 200), 'No expected completion from ' .. spec.server)

  assert(vim.wait(90000, function()
    for _, diagnostic in ipairs(vim.diagnostic.get(buf)) do
      if diagnostic.lnum == spec.diagnostic_line
          and diagnostic.severity == vim.diagnostic.severity.ERROR then
        return true
      end
    end
    return false
  end, 100), 'No expected type-error diagnostic from ' .. spec.server)
end

local function check_diff()
  assert(vim.fn.exists(':DiffTool') == 2, 'Built-in DiffTool was not loaded')
  assert(vim.wait(10000, function()
    local count = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.wo[win].diff then count = count + 1 end
    end
    return #vim.fn.getqflist() > 0 and count == 2
  end, 50), 'DiffTool did not create the file list and two diff windows')

  local entries = vim.fn.getqflist()
  assert(#entries == #spec.files, 'Unexpected changed-file count: ' .. vim.inspect(entries))
  for i, expected in ipairs(spec.files) do
    local entry = entries[i]
    assert(entry.user_data.rel == expected.path, vim.inspect(entry))
    assert(entry.text == expected.status, vim.inspect(entry))
    for _, side in ipairs({ 'left', 'right' }) do
      local path = entry.user_data[side]
      local content = vim.fn.filereadable(path) == 1
          and table.concat(vim.fn.readfile(path), '\n') .. '\n' or ''
      assert(content == expected[side], side .. ' content mismatch for ' .. expected.path)
    end
  end

  for _, server in ipairs({ 'gopls', 'pyright', 'ts_ls', 'rust_analyzer' }) do
    assert(not vim.lsp.is_enabled(server), 'LSP enabled in diff mode: ' .. server)
  end
  assert(#vim.lsp.get_clients() == 0, 'LSP started in a diff session')

  if spec.edit then
    local target = entries[1].user_data.right
    local buf = vim.fn.bufnr(target)
    assert(buf ~= -1 and vim.api.nvim_buf_is_loaded(buf), 'Right diff buffer is not loaded')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { spec.edit })
    vim.api.nvim_buf_call(buf, function() vim.cmd.write() end)
  end
  vim.fn.writefile({ 'ok' }, vim.env.NVIM_SMOKE_RESULT)
end

vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    vim.schedule(function()
      local ok, err = xpcall(spec.mode == 'lsp' and check_lsp or check_diff, debug.traceback)
      if not ok then
        io.stderr:write(tostring(err) .. '\n')
        vim.cmd('cquit 1')
      else
        vim.cmd('qa!')
      end
    end)
  end,
})
'''


def run(args, cwd, env):
    result = subprocess.run(
        args, cwd=cwd, env=env, text=True, capture_output=True, timeout=300
    )
    if result.returncode:
        raise RuntimeError(
            f"{args!r} failed ({result.returncode})\n{result.stdout}{result.stderr}"
        )
    return result.stdout


def write(root, name, content):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    return path


def check_lsp(root, env, nvim):
    fixtures = [
        (
            "gopls", "module/main.go", {
                "go.work": "go 1.22\nuse ./module\n",
                "module/go.mod": "module smoke.local/check\n\ngo 1.22\n",
            },
            'package main\nfunc answer() int { return 42 }\nfunc main() {\n'
            '  _ = answer()\n  var wrong string = 42\n  _ = wrong\n}\n',
        ),
        (
            "pyright", "main.py", {"pyrightconfig.json": '{"typeCheckingMode":"basic"}'},
            'def answer() -> int:\n    return 42\nvalue = answer()\nwrong: str = 42\n',
        ),
        (
            "ts_ls", "main.ts", {"tsconfig.json": '{"compilerOptions":{"strict":true}}'},
            'function answer(): number { return 42; }\nconst value = answer();\n'
            'const wrong: string = 42;\n',
        ),
        (
            "rust_analyzer", "member/src/main.rs", {
                "Cargo.toml": '[workspace]\nmembers = ["member"]\nresolver = "2"\n',
                "member/Cargo.toml": '[package]\nname = "nvim-smoke"\nversion = "0.1.0"\nedition = "2021"\n',
            },
            'fn answer() -> i32 { 42 }\nfn main() {\n    let _value = answer();\n'
            '    let _wrong: &str = 42;\n}\n',
        ),
    ]
    for server, filename, project_files, source in fixtures:
        project = root / server
        for name, content in project_files.items():
            write(project, name, content)
        path = write(project, filename, source)
        if server == "rust_analyzer":
            run(["cargo", "generate-lockfile", "--offline"], project, env)
        lines = source.splitlines()
        line = max(i for i, text in enumerate(lines) if "answer()" in text)
        spec = {
            "mode": "lsp", "server": server, "root": str(project),
            "line": line, "character": lines[line].index("answer"),
            "diagnostic_line": next(i for i, text in enumerate(lines) if "wrong" in text),
        }
        run(
            [nvim, "--headless", "-i", "NONE", str(path), "-c",
             "lua dofile(vim.env.NVIM_SMOKE_DRIVER)"],
            project, env | {"NVIM_SMOKE_SPEC": json.dumps(spec)},
        )
        print(f"Neovim {server}: attached, definition/completion resolved, type error diagnosed", flush=True)


def check_diff(root, env, nvim):
    shim_dir = root / "bin"
    shim = write(shim_dir, "nvim", '#!/bin/sh\nexec "$NVIM_SMOKE_REAL_NVIM" '
                 '--headless -i NONE -c "lua dofile(vim.env.NVIM_SMOKE_DRIVER)" "$@"\n')
    shim.chmod(0o755)
    result_file = root / "diff-result"
    env = env | {
        "PATH": f"{shim_dir}:{env['PATH']}",
        "NVIM_SMOKE_REAL_NVIM": nvim,
        "NVIM_SMOKE_RESULT": str(result_file),
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_NOSYSTEM": "1",
    }
    repo = root / "git"
    repo.mkdir()

    def git(*args):
        return run(["git", *args], repo, env)

    def compare(args, files, edit=None):
        result_file.unlink(missing_ok=True)
        spec = {"mode": "diff", "files": sorted(files, key=lambda f: f["path"])}
        if edit:
            spec["edit"] = edit
        run(["git", "ndiff", *args], repo, env | {"NVIM_SMOKE_SPEC": json.dumps(spec)})
        assert result_file.read_text() == "ok\n", "Neovim comparison was not exercised"

    def entry(path, left, right, status="M"):
        return {"path": path, "left": left, "right": right, "status": status}

    git("init", "-q")
    git("config", "user.name", "Neovim smoke test")
    git("config", "user.email", "smoke@example.invalid")
    write(repo, "space name.py", "value = 10\n")
    write(repo, "deleted.py", "deleted = True\n")
    git("add", ".")
    git("-c", "commit.gpgsign=false", "commit", "-qm", "fixture")
    write(repo, "space name.py", "value = 20\n")
    write(repo, "added.py", "added = True\n")
    (repo / "deleted.py").unlink()
    git("add", "-A")
    write(repo, "space name.py", "value = 30\n")

    compare([], [entry("space name.py", "value = 20\n", "value = 30\n")])
    compare(["--cached"], [
        entry("added.py", "", "added = True\n", "A"),
        entry("deleted.py", "deleted = True\n", "", "D"),
        entry("space name.py", "value = 10\n", "value = 20\n"),
    ])
    compare(["HEAD", "--", "space name.py"], [
        entry("space name.py", "value = 10\n", "value = 30\n"),
    ], edit="value = 40")
    assert (repo / "space name.py").read_text() == "value = 40\n"
    assert git("show", ":space name.py") == "value = 20\n", "Diff edit changed the index"

    git("reset", "--hard", "-q", "HEAD")
    result_file.unlink(missing_ok=True)
    git("ndiff")
    assert not result_file.exists(), "Clean repository unexpectedly opened Neovim"
    print("git ndiff: scopes, paths, file changes, editable diff, and clean repository passed", flush=True)


def main():
    nvim = shutil.which("nvim")
    assert nvim, "Neovim is not on PATH"
    with tempfile.TemporaryDirectory(prefix="neovim-smoke-") as directory:
        # macOS temp paths may use /var or /tmp symlinks; Neovim resolves them.
        root = Path(directory).resolve()
        driver = write(root, "driver.lua", LUA_DRIVER)
        env = os.environ | {"NVIM_SMOKE_DRIVER": str(driver), "CARGO_NET_OFFLINE": "true"}
        check_lsp(root, env, nvim)
        check_diff(root, env, nvim)


if __name__ == "__main__":
    main()
