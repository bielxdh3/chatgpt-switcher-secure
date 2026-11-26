"""Read-only Orca status tool over MCP stdio. No generic command interface."""
import json
import os
import subprocess
import sys

ORCA = r"E:\Orca\app\resources\bin\orca.exe"
CWD = r"E:\Orca\app"
ENV_KEYS = frozenset(("SYSTEMROOT", "WINDIR", "SYSTEMDRIVE", "USERPROFILE",
                      "APPDATA", "LOCALAPPDATA", "USERNAME", "HOMEDRIVE",
                      "HOMEPATH", "TEMP", "TMP", "COMSPEC"))
VERSIONS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
TOOL = {
    "name": "orca_status",
    "description": "Read whether the installed local Orca application and runtime are reachable. No actions or changes.",
    "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    "annotations": {"readOnlyHint": True, "destructiveHint": False,
                    "idempotentHint": True, "openWorldHint": False},
}


def status():
    def failed(reason):
        return {"ok": False, "reason": reason}
    env = {k: v for k, v in os.environ.items() if k.upper() in ENV_KEYS}
    try:
        run = subprocess.run([ORCA, "status", "--json"], cwd=CWD,
                             env=env, shell=False, stdin=subprocess.DEVNULL,
                             capture_output=True, encoding="utf-8", errors="replace", timeout=10)
    except subprocess.TimeoutExpired:
        return failed("timeout")
    except OSError:
        return failed("launch_failed")
    if run.returncode:
        return failed("runtime_access_denied" if "runtime_access_denied" in run.stdout else "status_failed")
    try:
        data = json.loads(run.stdout)
        if data["ok"] is not True:
            return failed("status_failed")
        app = data["result"]["app"]
        runtime = data["result"]["runtime"]
        if not isinstance(app["running"], bool) or not isinstance(runtime["reachable"], bool):
            return failed("invalid_status")
        state = runtime["state"]
        if state not in ("ready", "not_running", "starting", "unreachable", "error", "degraded"):
            state = "unknown"
        return {"ok": True, "app_running": app["running"], "runtime_state": state,
                "reachable": runtime["reachable"], "connected": runtime.get("connectionState") == "connected"}
    except (ValueError, KeyError, TypeError, AttributeError):
        return failed("invalid_status")


def handle(request):
    if not isinstance(request, dict) or request.get("jsonrpc") != "2.0":
        return {"jsonrpc": "2.0", "id": None, "error": {"code": -32600, "message": "Invalid Request"}}
    if "id" not in request:
        return None
    rid = request["id"]
    def result(value):
        return {"jsonrpc": "2.0", "id": rid, "result": value}
    def error(code, message):
        return {"jsonrpc": "2.0", "id": rid, "error": {"code": code, "message": message}}
    method = request.get("method")
    params = request.get("params", {})
    if not isinstance(params, dict):
        return error(-32602, "Invalid params")
    if method == "initialize":
        requested = params.get("protocolVersion")
        return result({"protocolVersion": requested if requested in VERSIONS else VERSIONS[0],
                       "capabilities": {"tools": {}},
                       "serverInfo": {"name": "orca-status", "version": "0.1.0"}})
    if method == "ping":
        return result({})
    if method == "tools/list":
        return result({"tools": [TOOL]})
    if method == "tools/call":
        if params.get("name") != TOOL["name"] or params.get("arguments", {}) != {}:
            return error(-32602, "Only orca_status with no arguments is supported")
        value = status()
        return result({"content": [{"type": "text", "text": json.dumps(value)}],
                       "isError": not value["ok"]})
    return error(-32601, "Method not found")


def main():
    for line in sys.stdin:
        try:
            response = handle(json.loads(line))
        except (ValueError, TypeError):
            response = {"jsonrpc": "2.0", "id": None,
                        "error": {"code": -32700, "message": "Parse error"}}
        if response is not None:
            print(json.dumps(response), flush=True)


if __name__ == "__main__":
    main()
