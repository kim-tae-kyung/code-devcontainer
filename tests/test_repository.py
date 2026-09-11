"""Regression checks for launcher behavior and browser pins."""

import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class LauncherTests(unittest.TestCase):
    def launch(self, with_ssh=False, with_gitconfig=False, gitconfig_symlink=False, **options):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            host_home = work / "host home"
            host_home.mkdir()
            if with_ssh:
                (host_home / ".ssh").mkdir()
                (host_home / ".ssh" / "id_ed25519").write_text("test-only-key")
            if with_gitconfig:
                config = host_home / ".gitconfig"
                if gitconfig_symlink:
                    config.symlink_to(host_home / "git config target")
                config.write_text("[user]\n\tname = Test User\n")
            log = work / "calls.jsonl"
            log.touch()
            kubectl = work / "kubectl"
            kubectl.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "with open(os.environ['LAUNCH_TEST_LOG'], 'a') as log:\n"
                "    log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                "if sys.argv[1] not in ('run', 'wait', 'cp', 'exec'):\n"
                "    sys.exit(99)\n"
                "if sys.argv[1] == os.environ.get('LAUNCH_TEST_FAIL'):\n"
                "    sys.exit(7)\n"
                "if os.environ.get('LAUNCH_TEST_FAIL') == 'permissions' and ('chmod' in sys.argv or (sys.argv[-2] == '-c' and '-i' not in sys.argv)):\n"
                "    sys.exit(7)\n"
                "if '-i' in sys.argv and sys.stdin.read() != '[user]\\n\\tname = Test User\\n':\n"
                "    sys.exit(98)\n"
            )
            kubectl.chmod(0o755)
            env = dict(os.environ)
            for name in ("POD_NAME", "IMAGE", "NAMESPACE", "SERVICE_ACCOUNT", "NODE_NAME"):
                env.pop(name, None)
            env.update(PATH=f"{work}:{env['PATH']}", LAUNCH_TEST_LOG=str(log))
            # Use a fixture home so tests never read the operator's files.
            env["HOME"] = str(host_home)
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
        connection = result.stdout.split("Done! Connect:", 1)[1].strip()
        self.assertEqual(shlex.split(connection), ["kubectl", "exec", "-it", calls[0][1], "--", "herdr"])

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
        connection = result.stdout.split("Done! Connect:", 1)[1].strip()
        self.assertEqual(shlex.split(connection), ["kubectl", "exec", "-it", "dev-test", "--namespace=infra", "--", "herdr"])

    def test_failures_do_not_report_success(self):
        for failed_command in ("run", "wait"):
            with self.subTest(command=failed_command):
                result, calls = self.launch(LAUNCH_TEST_FAIL=failed_command)
                self.assertEqual(result.returncode, 7)
                self.assertNotIn("Done! Connect:", result.stdout)
                self.assertEqual(calls[-1][0], failed_command)

    def test_ssh_is_copied_after_readiness_with_private_permissions(self):
        for namespace in ("", "infra"):
            with self.subTest(namespace=namespace):
                result, calls = self.launch(with_ssh=True, POD_NAME="dev-test", NAMESPACE=namespace)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual([call[0] for call in calls], ["run", "wait", "exec", "cp", "exec"])
                for call in calls:
                    if namespace:
                        self.assertIn("--namespace=infra", call)
                    else:
                        self.assertFalse(any(arg.startswith("--namespace=") for arg in call))
                prepare, copy, permissions = calls[2:]
                self.assertEqual(prepare[prepare.index("--") + 1:], ["install", "-d", "-m", "700", "/home/node/.ssh"])
                self.assertTrue(copy[1].endswith("/host home/.ssh"))
                self.assertEqual(copy[2], "dev-test:/home/node/")
                self.assertIn("Done! Connect:", result.stdout)
                self.assertNotIn("test-only-key", result.stdout + result.stderr)
                # Exercise the permission command on real fixture files.
                with tempfile.TemporaryDirectory() as directory:
                    ssh = Path(directory) / ".ssh"
                    nested = ssh / "config.d"
                    nested.mkdir(parents=True)
                    key = ssh / "id_ed25519"
                    config = nested / "hosts"
                    key.touch(mode=0o644)
                    config.touch(mode=0o644)
                    command = permissions[-1].replace("/home/node/.ssh", shlex.quote(str(ssh)))
                    subprocess.run(["sh", "-c", command], check=True)
                    for path in (ssh, nested):
                        self.assertEqual(path.stat().st_mode & 0o777, 0o700)
                    for path in (key, config):
                        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_ssh_failures_do_not_report_success(self):
        for failed_command in ("cp", "exec", "permissions"):
            with self.subTest(command=failed_command):
                result, calls = self.launch(with_ssh=True, LAUNCH_TEST_FAIL=failed_command)
                self.assertEqual(result.returncode, 7)
                self.assertNotIn("Done! Connect:", result.stdout)
                self.assertEqual(calls[-1][0], "exec" if failed_command == "permissions" else failed_command)

    def test_gitconfig_is_copied_independently_or_alongside_ssh(self):
        for with_ssh in (False, True):
            for namespace in ("", "infra"):
                with self.subTest(with_ssh=with_ssh, namespace=namespace):
                    result, calls = self.launch(
                        with_ssh=with_ssh, with_gitconfig=True,
                        POD_NAME="dev-test", NAMESPACE=namespace,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    expected = ["run", "wait"] + (["exec", "cp", "exec"] if with_ssh else []) + ["exec", "exec"]
                    self.assertEqual([call[0] for call in calls], expected)
                    copy, permissions = calls[-2:]
                    self.assertIn("-i", copy)
                    self.assertIn("dev-test", copy)
                    self.assertEqual(copy[copy.index("--") + 1:], ["sh", "-c", "umask 077; cat > /home/node/.gitconfig"])
                    self.assertEqual(permissions[permissions.index("--") + 1:], ["chmod", "600", "/home/node/.gitconfig"])
                    for call in (copy, permissions):
                        if namespace:
                            self.assertIn("--namespace=infra", call)
                        else:
                            self.assertFalse(any(arg.startswith("--namespace=") for arg in call))
                    self.assertIn("Done! Connect:", result.stdout)

    def test_gitconfig_symlink_copies_file_contents(self):
        result, calls = self.launch(with_gitconfig=True, gitconfig_symlink=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in calls], ["run", "wait", "exec", "exec"])
        self.assertIn("-i", calls[2])

    def test_gitconfig_failures_do_not_report_success(self):
        for failed_command in ("exec", "permissions"):
            with self.subTest(command=failed_command):
                result, calls = self.launch(with_gitconfig=True, LAUNCH_TEST_FAIL=failed_command)
                self.assertEqual(result.returncode, 7)
                self.assertNotIn("Done! Connect:", result.stdout)
                self.assertEqual(calls[-1][0], "exec" if failed_command == "permissions" else failed_command)


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


if __name__ == "__main__":
    unittest.main()
