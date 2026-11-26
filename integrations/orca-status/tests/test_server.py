import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "plugins" / "orca-status"))
import server


class StatusTests(unittest.TestCase):
    def test_only_safe_fields(self):
        raw = {"ok": True, "result": {"app": {"running": True},
               "runtime": {"state": "ready", "reachable": True, "connectionState": "connected",
                           "runtimeId": "private", "token": "secret"}}}
        with patch.object(server.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, json.dumps(raw), "")) as run:
            result = server.status()
        self.assertEqual(result, {"ok": True, "app_running": True, "runtime_state": "ready",
                                  "reachable": True, "connected": True})
        args, kwargs = run.call_args
        self.assertEqual(args[0], [server.ORCA, "status", "--json"])
        self.assertFalse(kwargs["shell"])
        self.assertEqual(kwargs["timeout"], 10)
        self.assertNotIn("ORCA_PAIRING_CODE", kwargs["env"])

    def test_failure_closed(self):
        for code, value in [(1, '{"ok":true}'), (0, 'bad json'), (0, '{"ok":false}'), (0, '{"ok":true}')]:
            with self.subTest(code=code, value=value):
                with patch.object(server.subprocess, "run", return_value=subprocess.CompletedProcess([], code, value, "")):
                    self.assertFalse(server.status()["ok"])

    def test_timeout(self):
        with patch.object(server.subprocess, "run", side_effect=subprocess.TimeoutExpired([], 10)):
            self.assertFalse(server.status()["ok"])

    def test_no_arbitrary_args_or_tools(self):
        with patch.object(server, "status") as status:
            for params in [{"name": "exec", "arguments": {}},
                           {"name": "orca_status", "arguments": {"command": "whoami"}},
                           {"name": "orca_status", "arguments": None}]:
                self.assertIn("error", server.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": params}))
            status.assert_not_called()

    def test_tool_schema(self):
        result = server.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/list"})["result"]["tools"]
        self.assertEqual(len(result), 1)
        self.assertTrue(result[0]["annotations"]["readOnlyHint"])
        self.assertFalse(result[0]["inputSchema"]["additionalProperties"])

    def test_notification_no_response(self):
        self.assertIsNone(server.handle({"jsonrpc": "2.0", "method": "notifications/initialized"}))

    def test_initialize(self):
        response = server.handle({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                                  "params": {"protocolVersion": "2025-11-25"}})
        self.assertEqual(response["result"]["protocolVersion"], "2025-11-25")


if __name__ == "__main__":
    unittest.main()
