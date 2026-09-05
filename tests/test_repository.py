"""Regression checks for launcher behavior, browser pins, and documentation scope."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def load_script(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class LauncherTests(unittest.TestCase):
    def launch(self, **options):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            log = work / "calls.jsonl"
            log.touch()
            kubectl = work / "kubectl"
            kubectl.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "with open(os.environ['LAUNCH_TEST_LOG'], 'a') as log:\n"
                "    log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                "if sys.argv[1] not in ('run', 'wait'):\n"
                "    sys.exit(99)\n"
                "if sys.argv[1] == os.environ.get('LAUNCH_TEST_FAIL'):\n"
                "    sys.exit(7)\n"
            )
            kubectl.chmod(0o755)
            env = dict(os.environ)
            for name in ("POD_NAME", "IMAGE", "NAMESPACE", "SERVICE_ACCOUNT", "NODE_NAME"):
                env.pop(name, None)
            env.update(PATH=f"{work}:{env['PATH']}", LAUNCH_TEST_LOG=str(log))
            env.update(options)
            result = subprocess.run(
                ["bash", str(ROOT / "run-k8s-daemon-example.sh")],
                env=env, text=True, capture_output=True,
            )
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            return result, calls

    def test_defaults_create_and_wait_without_copying(self):
        result, calls = self.launch()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in calls], ["run", "wait"])
        self.assertIn("--image-pull-policy=Always", calls[0])
        self.assertTrue(calls[0][1].startswith("devcontainer-"))
        self.assertNotIn("--namespace=", result.stdout)
        self.assertIn("Done! Connect:", result.stdout)

    def test_options_preserve_cluster_access_and_scheduling(self):
        result, calls = self.launch(
            POD_NAME="dev-test", IMAGE="example/image:tag", NAMESPACE="infra",
            SERVICE_ACCOUNT="dev-admin", NODE_NAME="control-plane-0",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        for call in calls:
            self.assertIn("--namespace=infra", call)
        self.assertIn("--image=example/image:tag", calls[0])
        overrides = next(arg.split("=", 1)[1] for arg in calls[0] if arg.startswith("--overrides="))
        spec = json.loads(overrides)["spec"]
        self.assertEqual(spec["serviceAccountName"], "dev-admin")
        self.assertEqual(spec["nodeName"], "control-plane-0")
        self.assertTrue(spec["shareProcessNamespace"])
        self.assertEqual(len(spec["tolerations"]), 2)
        self.assertNotIn("automountServiceAccountToken", spec)

    def test_failures_do_not_report_success(self):
        for failed_command in ("run", "wait"):
            with self.subTest(command=failed_command):
                result, calls = self.launch(LAUNCH_TEST_FAIL=failed_command)
                self.assertEqual(result.returncode, 7)
                self.assertNotIn("Done! Connect:", result.stdout)
                self.assertEqual(calls[-1][0], failed_command)


class PlaywrightPinTests(unittest.TestCase):
    def test_source_pin(self):
        subprocess.run([sys.executable, "scripts/check_playwright_pin.py"], cwd=ROOT, check=True)

    def test_mismatched_agent_registration_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config.toml"
            config.write_text((ROOT / "codex-config.toml").read_text().replace("@playwright/mcp@", "@playwright/mcp@9"))
            result = subprocess.run(
                [sys.executable, "scripts/check_playwright_pin.py", "--codex-config", str(config)],
                cwd=ROOT, capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Codex Playwright registration", result.stderr)

    def test_mismatched_claude_registration_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "claude.json"
            config.write_text(json.dumps({"mcpServers": {"playwright": {"command": "npx", "args": ["@playwright/mcp@latest"]}}}))
            result = subprocess.run(
                [sys.executable, "scripts/check_playwright_pin.py", "--claude-config", str(config)],
                cwd=ROOT, capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Claude Code Playwright registration", result.stderr)


class DocumentationScopeTests(unittest.TestCase):
    def test_generated_subtrees_are_skipped_but_explicit_targets_work(self):
        base = ".agents/skills/docs-visual/scripts/"
        checker = load_script("docs_checker", base + "validate_docs.py")
        renderer = load_script("docs_renderer", base + "render_mermaid.py")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            owned = root / ".agents" / "guide.md"
            owned.parent.mkdir()
            owned.write_text("# Guide\n")
            for excluded in (".git", "node_modules", ".venv", "__pycache__"):
                (root / excluded).mkdir()
                (root / excluded / "README.md").write_text("# Dependency\n")
            for scan in (checker.markdown_files, lambda path: renderer.markdown_files([path])):
                self.assertEqual(scan(root), [owned])
                selected = root / "node_modules" / "README.md"
                self.assertEqual(scan(selected), [selected])
                self.assertEqual(scan(selected.parent), [selected])


if __name__ == "__main__":
    unittest.main()
