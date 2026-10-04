"""Check automatic Remote Control routing without real host credentials."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
WRAPPER = Path(os.environ.get("CODEX_WRAPPER", ROOT / "scripts" / "codex"))
HERDR_VARS = ("HERDR_ENV", "HERDR_SOCKET_PATH", "HERDR_PANE_ID")


class CodexRemoteTests(unittest.TestCase):
    def invoke(self, *args, fail_start=False, missing_cli=False, recursive_cli=False):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            log = work / "calls.jsonl"
            stub = work / "codex-real"
            stub.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "with open(os.environ['REMOTE_TEST_LOG'], 'a') as log:\n"
                "    log.write(json.dumps({'args': sys.argv[1:], 'pane': "
                "{k: os.environ.get(k) for k in " + repr(HERDR_VARS) + "}, "
                "'codex_home': os.environ.get('CODEX_HOME')}) + '\\n')\n"
                "if sys.argv[1:] == ['remote-control', 'start']:\n"
                "    if os.environ['REMOTE_TEST_FAIL'] == '1':\n"
                "        print('remote startup failed', file=sys.stderr)\n"
                "        sys.exit(7)\n"
                "    print('daemon ready')\n"
                "else:\n"
                "    print('fixture command')\n"
            )
            stub.chmod(0o755)
            env = dict(os.environ)
            env.update(
                CODEX_CLI_BIN=str(WRAPPER if recursive_cli else work / "missing" if missing_cli else stub),
                REMOTE_TEST_LOG=str(log), REMOTE_TEST_FAIL=str(int(fail_start)),
                CODEX_HOME=str(work / "codex state"),
                HERDR_ENV="1", HERDR_SOCKET_PATH="/tmp/fixture.sock", HERDR_PANE_ID="pane-2",
            )
            result = subprocess.run([str(WRAPPER), *args], env=env, capture_output=True, text=True)
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    def test_session_routes_to_daemon_without_capturing_pane(self):
        result, calls = self.invoke("-C", "/workspace/project with spaces", "explain $(literal) `prompt`")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[0]["args"], ["remote-control", "start"])
        self.assertEqual(calls[0]["pane"], dict.fromkeys(HERDR_VARS))
        self.assertEqual(calls[1]["args"], [
            "--remote", "unix://", "--yolo", "-C", "/workspace/project with spaces",
            "explain $(literal) `prompt`",
        ])
        self.assertEqual(calls[1]["pane"]["HERDR_PANE_ID"], "pane-2")
        self.assertEqual(calls[0]["codex_home"], calls[1]["codex_home"])
        self.assertNotIn("daemon ready", result.stdout)

    def test_plain_codex_always_connects(self):
        result, calls = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[-1]["args"], ["--remote", "unix://", "--yolo"])

    def test_control_commands_do_not_capture_pane(self):
        for action in ("start", "pair", "stop"):
            with self.subTest(action=action):
                result, calls = self.invoke("remote-control", action, "--json")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual([call["args"] for call in calls], [["remote-control", action, "--json"]])
                self.assertEqual(calls[0]["pane"], dict.fromkeys(HERDR_VARS))
                self.assertIn("fixture command", result.stdout)

    def test_start_failure_never_launches_unconnected_tui(self):
        result, calls = self.invoke(fail_start=True)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(len(calls), 1)
        self.assertIn("remote startup failed", result.stderr)

    def test_remote_commands_keep_routing(self):
        for action in ("resume", "fork", "agents", "archive", "delete", "unarchive"):
            with self.subTest(action=action):
                result, calls = self.invoke(action, "fixture-session")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(calls[-1]["args"], ["--remote", "unix://", "--yolo", action, "fixture-session"])

    def test_utility_commands_are_passed_through(self):
        for args in (("--version",), ("--help",), ("resume", "--help"),
                     ("login", "--device-auth"), ("exec", "--json", "prompt"),
                     ("-c", 'web_search="live"', "exec", "prompt"),
                     ("review", "--uncommitted"), ("app-server", "--listen", "stdio://"),
                     ("features", "list"), ("mcp", "list")):
            with self.subTest(args=args):
                result, calls = self.invoke(*args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual([call["args"] for call in calls], [list(args)])
                self.assertEqual(calls[0]["pane"]["HERDR_PANE_ID"], "pane-2")

    def test_global_option_values_are_not_subcommands(self):
        for args in (("-C", "exec"), ("-m", "review"), ("--cd=exec",),
                     ("-c", 'note="--no-daemon"'), ("--", "exec"), ("--", "--no-daemon")):
            with self.subTest(args=args):
                result, calls = self.invoke(*args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(calls[-1]["args"], ["--remote", "unix://", "--yolo", *args])

    def test_embedded_and_other_host_overrides_are_rejected(self):
        for args in (("--no-daemon",), ("resume", "fixture", "--no-daemon"),
                     ("--remote", "ws://example:9000"), ("--remote=unix:///other.sock",)):
            with self.subTest(args=args):
                result, calls = self.invoke(*args)
                self.assertEqual(result.returncode, 2)
                self.assertIn("always use the local Remote Control daemon", result.stderr)
                self.assertEqual(calls, [])

    def test_explicit_bypass_flag_is_not_duplicated(self):
        for flag in ("--yolo", "--dangerously-bypass-approvals-and-sandbox"):
            with self.subTest(flag=flag):
                result, calls = self.invoke("resume", "fixture", flag)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(calls[-1]["args"], ["--remote", "unix://", "resume", "fixture", flag])

    def test_missing_and_recursive_cli_fail_without_starting(self):
        for kwargs in ({"missing_cli": True}, {"recursive_cli": True}):
            with self.subTest(kwargs=kwargs):
                result, calls = self.invoke(**kwargs)
                self.assertEqual(result.returncode, 127)
                self.assertIn("original CLI missing or points to the wrapper", result.stderr)
                self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
