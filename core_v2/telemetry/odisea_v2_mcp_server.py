#!/usr/bin/env python3
"""Odisea V2 MCP stdio server — thin proxy over the FD-162 telemetry peer (:4999).

This is the modern successor to core_v2/anna/client/odisea_mcp_stdio_server.py (which
spoke the deprecated ANNA V1 TCP bridge on :5000). It exposes the live-game debugging
surface as MCP tools, but every tool just forwards to the peer's HTTP API:

    MCP tool call  ->  HTTP to http://127.0.0.1:4999/{status,command,eval,...}  ->  ANNAV2

Before the first call it runs tools/ensure_peer.sh so the peer is always up (idempotent;
a no-op if it already answers /health). The game auto-discovers the peer over mDNS/UDP and
— since the ANNAV2_Thread peer-upgrade fix — will switch from the central fallback to this
local peer within a few seconds even if the peer was launched after the game.

CLI mode (handy for scripts / quick pokes without an MCP client):
    python3 odisea_v2_mcp_server.py --tool inspect_node --args-json '{"path":"/root"}'
    python3 odisea_v2_mcp_server.py --tool eval --args-json '{"expr":"get_tree().get_node_count()"}'
    python3 odisea_v2_mcp_server.py --status
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional

MCP_PROTOCOL_VERSION = "2025-06-18"
SERVER_INFO = {"name": "odisea-mcp", "version": "2.0.0"}

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ENSURE_PEER = os.path.join(REPO_ROOT, "tools", "ensure_peer.sh")

PEER_HOST = os.environ.get("ODISEA_PEER_HOST", "127.0.0.1")
PEER_PORT = os.environ.get("ODISEA_PEER_PORT", "4999")
HTTP_TIMEOUT = float(os.environ.get("ODISEA_MCP_TIMEOUT", "8.0"))
PEER_BASE = "http://%s:%s" % (PEER_HOST, PEER_PORT)

_peer_ensured = False


# --------------------------------------------------------------------------- peer plumbing
def ensure_peer() -> None:
    """Run ensure_peer.sh once per process so the peer is alive before we hit it."""
    global _peer_ensured
    if _peer_ensured:
        return
    _peer_ensured = True
    if not os.path.exists(ENSURE_PEER):
        return  # script missing: assume the user manages the peer themselves
    try:
        subprocess.run(
            ["bash", ENSURE_PEER, "--quiet"],
            cwd=REPO_ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=20,
        )
    except Exception:
        pass  # the HTTP call below will surface a clean "peer unreachable" error


def _http(method: str, path: str, body: Optional[Dict[str, Any]] = None,
          query: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    ensure_peer()
    url = PEER_BASE + path
    if query:
        url += "?" + urllib.parse.urlencode({k: v for k, v in query.items() if v is not None})
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:  # peer returned a structured error body
        try:
            return json.loads(exc.read().decode("utf-8"))
        except Exception:
            return {"error": "http_%d" % exc.code, "message": str(exc)}
    except Exception as exc:
        return {"error": "peer_unreachable",
                "message": "Could not reach the telemetry peer at %s: %s" % (PEER_BASE, exc),
                "hint": "Start the game (F5) with ANNAV2 and ensure tools/ensure_peer.sh can run."}


def _command(action: str, args: Optional[Dict[str, Any]] = None,
             player_id: Optional[str] = None) -> Dict[str, Any]:
    body: Dict[str, Any] = {"action": action, "args": args or {}}
    if player_id:
        body["player_id"] = player_id
    return _http("POST", "/command", body=body)


# --------------------------------------------------------------------------- tool dispatch
def call_tool(name: str, args: Dict[str, Any]) -> Dict[str, Any]:
    args = args or {}
    pid = args.get("player_id")
    if name == "status":
        return _http("GET", "/status", query={"player_id": pid} if pid else None)
    if name == "health":
        return _http("GET", "/health")
    if name == "sessions":
        return _http("GET", "/sessions")
    if name == "peers":
        return _http("GET", "/peers")
    if name == "eval":
        return _http("GET", "/eval", query={"expr": args["expr"], "player_id": pid})
    if name == "inspect_node":
        return _command("inspect_node", {"path": args["path"]}, pid)
    if name == "set_property":
        return _command("set_property",
                        {"path": args["path"], "property": args["property"], "value": args["value"]}, pid)
    if name == "execute_script":
        return _command("execute_script", {"script": args["script"]}, pid)
    if name == "screenshot":
        return _command("screenshot", {}, pid)
    if name == "teleport_player":
        return _command("teleport_player", {"position": args["position"]}, pid)
    if name == "spawn_scene":
        return _command("spawn_scene", {"path": args["path"]}, pid)
    return {"error": "unknown_tool", "message": name}


def _obj(props: Dict[str, Any], required: Optional[List[str]] = None) -> Dict[str, Any]:
    schema: Dict[str, Any] = {"type": "object", "properties": props}
    if required:
        schema["required"] = required
    return schema


_PID = {"player_id": {"type": "string",
                      "description": "Target a specific connected game; omit for the most recent."}}

TOOL_SCHEMAS: List[Dict[str, Any]] = [
    {"name": "status", "description": "Live telemetry heartbeat(s): scene, position, velocity, fps, mem.",
     "inputSchema": _obj(dict(_PID))},
    {"name": "health", "description": "Peer health: games_connected, players_known, central_connected.",
     "inputSchema": _obj({})},
    {"name": "sessions", "description": "Active session ids known to the peer.", "inputSchema": _obj({})},
    {"name": "peers", "description": "Connected player ids.", "inputSchema": _obj({})},
    {"name": "eval", "description": "Evaluate a GDScript expression in the running game (wraps `return <expr>`).",
     "inputSchema": _obj(dict(_PID, expr={"type": "string", "description": "GDScript expression, e.g. get_tree().get_node_count()"}),
                         ["expr"])},
    {"name": "inspect_node", "description": "Inspect a SceneTree node (type, children, transform if Spatial).",
     "inputSchema": _obj(dict(_PID, path={"type": "string", "description": "Absolute node path, e.g. /root/Pilot"}),
                         ["path"])},
    {"name": "set_property", "description": "Set a property on a live node (debug builds only).",
     "inputSchema": _obj(dict(_PID, path={"type": "string"}, property={"type": "string"},
                              value={"description": "New value (any JSON type)."}),
                         ["path", "property", "value"])},
    {"name": "execute_script", "description": "Run a GDScript body in the running game (debug builds only).",
     "inputSchema": _obj(dict(_PID, script={"type": "string", "description": "GDScript body; use `return` to send a value back."}),
                         ["script"])},
    {"name": "screenshot", "description": "Capture a screenshot of the running game; returns the file path.",
     "inputSchema": _obj(dict(_PID))},
    {"name": "teleport_player", "description": "Teleport the player to a world position [x, y, z].",
     "inputSchema": _obj(dict(_PID, position={"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3}),
                         ["position"])},
    {"name": "spawn_scene", "description": "Instance a .tscn into the running scene (debug builds only).",
     "inputSchema": _obj(dict(_PID, path={"type": "string", "description": "res:// path to a .tscn"}), ["path"])},
]


# --------------------------------------------------------------------------- MCP stdio loop
def _ok(msg_id: Any, result: Dict[str, Any]) -> Dict[str, Any]:
    return {"jsonrpc": "2.0", "id": msg_id, "result": result}


def _err(msg_id: Any, code: int, message: str) -> Dict[str, Any]:
    return {"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": message}}


def _write(msg: Dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(msg, separators=(",", ":"), ensure_ascii=True) + "\n")
    sys.stdout.flush()


def _content(payload: Dict[str, Any]) -> Dict[str, Any]:
    return {"content": [{"type": "text", "text": json.dumps(payload, ensure_ascii=False, indent=2)}]}


def run_stdio_server() -> int:
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        method = msg.get("method")
        msg_id = msg.get("id")

        if method == "initialize":
            _write(_ok(msg_id, {
                "protocolVersion": MCP_PROTOCOL_VERSION,
                "serverInfo": SERVER_INFO,
                "capabilities": {"tools": {}},
            }))
        elif method == "notifications/initialized":
            continue
        elif method == "ping":
            _write(_ok(msg_id, {}))
        elif method == "tools/list":
            _write(_ok(msg_id, {"tools": TOOL_SCHEMAS}))
        elif method == "tools/call":
            params = msg.get("params", {})
            name = params.get("name", "")
            args = params.get("arguments", {}) or {}
            try:
                _write(_ok(msg_id, _content(call_tool(name, args))))
            except KeyError as exc:
                _write(_ok(msg_id, _content({"error": "missing_argument", "message": str(exc)})))
            except Exception as exc:
                _write(_err(msg_id, -32000, str(exc)))
        elif msg_id is not None:
            _write(_err(msg_id, -32601, "Method not found: %s" % method))
    return 0


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(description="Odisea V2 MCP server (proxy over telemetry peer :4999)")
    p.add_argument("--tool", help="Call a tool directly and print JSON, then exit.")
    p.add_argument("--args-json", default="{}", help="JSON args for --tool.")
    p.add_argument("--status", action="store_true", help="Shortcut for --tool status.")
    ns = p.parse_args(argv)

    if ns.status:
        print(json.dumps(call_tool("status", {}), indent=2, ensure_ascii=False))
        return 0
    if ns.tool:
        try:
            args = json.loads(ns.args_json)
        except Exception as exc:
            print(json.dumps({"error": "bad_args_json", "message": str(exc)}))
            return 2
        print(json.dumps(call_tool(ns.tool, args), indent=2, ensure_ascii=False))
        return 0

    return run_stdio_server()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
