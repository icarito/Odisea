#!/usr/bin/env python3
"""Odisea MCP stdio server + direct TCP client stub.

Default mode:
  Runs an MCP stdio server for VS Code and proxies tools/resources to AnnaBridge.

CLI mode:
  python3 odisea_mcp_stdio_server.py --tool inspect_node --args-json '{"node_path":"/root/Pilot"}'
  python3 odisea_mcp_stdio_server.py --resource odisea://scene/hierarchy
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import socket
import subprocess
import sys
import time
import uuid
from typing import Any, Dict, List, Optional


MCP_PROTOCOL_VERSION = "2025-06-18"
SERVER_INFO = {"name": "odisea-mcp", "version": "0.1.0"}

RESOURCE_SCHEMAS: List[Dict[str, Any]] = [
    {
        "uri": "odisea://scene/hierarchy",
        "name": "Scene Hierarchy",
        "description": "Depth-limited SceneTree JSON (name/type/path).",
        "mimeType": "application/json",
    },
    {
        "uri": "odisea://simulation/telemetry",
        "name": "Simulation Telemetry",
        "description": "Player/Elias position, velocity, active OYS line, FPS.",
        "mimeType": "application/json",
    },
    {
        "uri": "odisea://olcs/logic-state",
        "name": "OLCS Logic State",
        "description": "Grouped Levers/Doors/Gates logical values.",
        "mimeType": "application/json",
    },
]

TOOL_SCHEMAS: List[Dict[str, Any]] = [
    {
        "name": "bridge_status",
        "description": "Return current Odisea MCP bridge status (host/port/process).",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "bridge_connect",
        "description": "Connect MCP proxy to an already running AnnaBridge TCP endpoint.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "host": {"type": "string", "description": "Default 127.0.0.1"},
                "port": {"type": "number", "description": "Default 5000"},
                "timeout_s": {"type": "number", "description": "Probe timeout"},
            },
        },
    },
    {
        "name": "bridge_launch",
        "description": "Launch Godot runtime with ANNA enabled and auto-connect MCP proxy.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "project_path": {"type": "string", "description": "Project root path"},
                "godot_exe": {"type": "string", "description": "Godot 3 executable (default: godot3-bin)"},
                "host": {"type": "string", "description": "Default 127.0.0.1"},
                "port": {"type": "number", "description": "Default 5000"},
                "headless": {"type": "boolean", "description": "Launch with --no-window"},
                "timeout_s": {"type": "number", "description": "Startup probe timeout"},
            },
        },
    },
    {
        "name": "bridge_reset",
        "description": "Terminate launched Godot process (if any) and launch again.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "project_path": {"type": "string"},
                "godot_exe": {"type": "string"},
                "host": {"type": "string"},
                "port": {"type": "number"},
                "headless": {"type": "boolean"},
                "timeout_s": {"type": "number"},
            },
        },
    },
    {
        "name": "bridge_stop",
        "description": "Stop Godot process launched by MCP bridge (if running).",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "inspect_node",
        "description": "Inspect node exported properties and runtime state by path.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "node_path": {"type": "string", "description": "NodePath, e.g. /root/Main/Pilot"},
                "include_children": {"type": "boolean", "description": "Include serialized child subtree."},
                "include_visual": {"type": "boolean", "description": "Include mesh/material/light runtime details."},
                "max_depth": {"type": "number", "description": "Child/visual traversal depth (0-8)."},
                "max_children": {"type": "number", "description": "Per-node child cap (1-256)."},
                "probe_fields": {
                    "type": "array",
                    "description": "Runtime node fields to probe (can include non-export vars).",
                    "items": {"type": "string"},
                },
            },
            "required": ["node_path"],
        },
    },
    {
        "name": "set_property",
        "description": "Set a runtime node property by path. Supports nested property paths like environment.glow_enabled.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "node_path": {"type": "string", "description": "NodePath, e.g. /root/Main/WorldEnvironment"},
                "property": {"type": "string", "description": "Property name/path, e.g. environment.glow_enabled"},
                "value": {"description": "New property value. Can be bool/number/string/object/array."},
                "strict": {"type": "boolean", "description": "Fail if property does not exist (default true)."},
            },
            "required": ["node_path", "property", "value"],
        },
    },
    {
        "name": "execute_oys",
        "description": "Inject one OdysseyScript line via OYS console queue (deterministic path).",
        "inputSchema": {
            "type": "object",
            "properties": {"script_command": {"type": "string", "description": 'Example: PRINT "hola"'}},
            "required": ["script_command"],
        },
    },
    {
        "name": "capture_vision",
        "description": "Capture viewport screenshot, optionally returning base64.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "label": {"type": "string"},
                "include_base64": {"type": "boolean"},
            },
        },
    },
    {
        "name": "query_codex_docs",
        "description": "Search local README.md and TODO.md for a topic.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "topic": {"type": "string"},
                "max_matches": {"type": "number"},
            },
            "required": ["topic"],
        },
    },
]


class AnnaRuntimeProxy:
    def __init__(self, host: str, port: int, timeout_s: float) -> None:
        self.host = host
        self.port = port
        self.timeout_s = timeout_s

    def reconfigure(self, host: str, port: int, timeout_s: Optional[float] = None) -> None:
        self.host = host
        self.port = port
        if timeout_s is not None:
            self.timeout_s = timeout_s

    def call(self, action: str, args: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        request_id = str(uuid.uuid4())
        payload = {
            "type": "mcp_cmd",
            "id": request_id,
            "payload": {
                "action": action,
                "args": args or {},
            },
        }
        packet = (json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8")

        try:
            with socket.create_connection((self.host, self.port), timeout=self.timeout_s) as sock:
                sock.settimeout(self.timeout_s)
                sock.sendall(packet)
                response = self._wait_for_response(sock, request_id)
        except OSError as exc:
            raise RuntimeError(
                "Cannot reach AnnaBridge TCP server at %s:%d (%s). "
                "Run Godot with ANNA enabled first." % (self.host, self.port, exc)
            ) from exc

        if not isinstance(response, dict):
            raise RuntimeError("Invalid response payload from runtime bridge.")

        if not bool(response.get("ok", False)):
            err = response.get("error", "mcp_error")
            command = response.get("command", action)
            raise RuntimeError("Runtime command failed: %s (%s)" % (command, err))

        return response.get("data", {})

    def _wait_for_response(self, sock: socket.socket, request_id: str) -> Dict[str, Any]:
        deadline = time.monotonic() + self.timeout_s
        buffer = b""
        while time.monotonic() < deadline:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                if not line.strip():
                    continue
                try:
                    msg = json.loads(line.decode("utf-8"))
                except json.JSONDecodeError:
                    continue
                if not isinstance(msg, dict):
                    continue
                if str(msg.get("id", "")) != request_id:
                    continue
                msg_type = str(msg.get("type", ""))
                if msg_type not in ("mcp_result", "mcp_error"):
                    continue
                return msg
        raise RuntimeError("Timed out waiting for runtime response id=%s" % request_id)


def _resource_to_action(uri: str) -> str:
    if uri == "odisea://scene/hierarchy":
        return "get_tree"
    if uri == "odisea://simulation/telemetry":
        return "get_telemetry"
    if uri == "odisea://olcs/logic-state":
        return "get_olcs_state"
    raise ValueError("Unknown resource URI: %s" % uri)


class BridgeSessionManager:
    def __init__(self, proxy: AnnaRuntimeProxy) -> None:
        self.proxy = proxy
        self._launched_proc: Optional[subprocess.Popen] = None
        self._launched_cmd: List[str] = []
        self._launched_project: str = ""

    def status(self) -> Dict[str, Any]:
        proc_alive = self._launched_proc is not None and self._launched_proc.poll() is None
        pid = self._launched_proc.pid if proc_alive and self._launched_proc else None
        return {
            "host": self.proxy.host,
            "port": self.proxy.port,
            "timeout_s": self.proxy.timeout_s,
            "process_launched_by_mcp": proc_alive,
            "launched_pid": pid,
            "launched_project": self._launched_project,
            "launched_cmd": self._launched_cmd,
        }

    def connect(self, host: str, port: int, timeout_s: float) -> Dict[str, Any]:
        self.proxy.reconfigure(host=host, port=port, timeout_s=timeout_s)
        self._probe_runtime(timeout_s=timeout_s)
        out = self.status()
        out["connected"] = True
        return out

    def launch(
        self,
        project_path: str,
        godot_exe: str,
        host: str,
        port: int,
        headless: bool,
        timeout_s: float,
    ) -> Dict[str, Any]:
        self.stop()
        project_abs = os.path.abspath(project_path)
        if not os.path.isdir(project_abs):
            raise RuntimeError("project_path does not exist: %s" % project_abs)

        cmd = [godot_exe, "--path", project_abs]
        if headless:
            cmd.insert(1, "--no-window")

        env = dict(os.environ)
        env["ANNA_ENABLED"] = "1"
        env["ANNA_PORT"] = str(port)

        try:
            proc = subprocess.Popen(  # noqa: S603
                cmd,
                cwd=project_abs,
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError as exc:
            raise RuntimeError("Failed to launch Godot: %s" % exc) from exc

        self._launched_proc = proc
        self._launched_cmd = cmd
        self._launched_project = project_abs
        self.proxy.reconfigure(host=host, port=port, timeout_s=timeout_s)
        try:
            self._probe_runtime(timeout_s=timeout_s)
        except Exception:
            self.stop()
            raise

        out = self.status()
        out["connected"] = True
        return out

    def reset(
        self,
        project_path: str,
        godot_exe: str,
        host: str,
        port: int,
        headless: bool,
        timeout_s: float,
    ) -> Dict[str, Any]:
        self.stop()
        return self.launch(project_path, godot_exe, host, port, headless, timeout_s)

    def stop(self) -> None:
        if self._launched_proc is None:
            return
        if self._launched_proc.poll() is None:
            self._terminate_process_group(self._launched_proc)
        self._launched_proc = None
        self._launched_cmd = []
        self._launched_project = ""

    def stop_with_status(self) -> Dict[str, Any]:
        was_running = self._launched_proc is not None and self._launched_proc.poll() is None
        self.stop()
        out = self.status()
        out["stopped"] = True
        out["was_running"] = was_running
        return out

    def _probe_runtime(self, timeout_s: float) -> None:
        deadline = time.monotonic() + max(0.5, timeout_s)
        last_error: Optional[Exception] = None
        while time.monotonic() < deadline:
            try:
                self.proxy.call("get_tree", {"max_depth": 1})
                return
            except Exception as exc:  # pylint: disable=broad-except
                last_error = exc
                time.sleep(0.2)
        if last_error is not None:
            raise RuntimeError("Runtime probe failed: %s" % last_error)
        raise RuntimeError("Runtime probe failed.")

    def _terminate_process_group(self, proc: subprocess.Popen) -> None:
        try:
            pgid = os.getpgid(proc.pid)
        except OSError:
            pgid = None

        if pgid is not None:
            try:
                os.killpg(pgid, signal.SIGTERM)
            except OSError:
                pass
            try:
                proc.wait(timeout=4.0)
                return
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(pgid, signal.SIGKILL)
                except OSError:
                    pass
                proc.wait(timeout=2.0)
                return

        # Fallback for platforms without process groups or unexpected states.
        proc.terminate()
        try:
            proc.wait(timeout=4.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2.0)


def call_resource(session: BridgeSessionManager, uri: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    return session.proxy.call(_resource_to_action(uri), params or {})


def call_tool(session: BridgeSessionManager, name: str, args: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    a = args or {}
    if name == "bridge_status":
        return session.status()
    if name == "bridge_connect":
        host = str(a.get("host", session.proxy.host or "127.0.0.1"))
        port = int(a.get("port", session.proxy.port))
        timeout_s = float(a.get("timeout_s", session.proxy.timeout_s))
        return session.connect(host=host, port=port, timeout_s=timeout_s)
    if name == "bridge_launch":
        project_path = str(a.get("project_path", os.getenv("ODISEA_PROJECT_PATH", os.getcwd())))
        godot_exe = str(a.get("godot_exe", os.getenv("GODOT_BIN", "godot3-bin")))
        host = str(a.get("host", session.proxy.host or "127.0.0.1"))
        port = int(a.get("port", session.proxy.port))
        headless = bool(a.get("headless", False))
        timeout_s = float(a.get("timeout_s", session.proxy.timeout_s))
        return session.launch(
            project_path=project_path,
            godot_exe=godot_exe,
            host=host,
            port=port,
            headless=headless,
            timeout_s=timeout_s,
        )
    if name == "bridge_reset":
        project_path = str(a.get("project_path", os.getenv("ODISEA_PROJECT_PATH", os.getcwd())))
        godot_exe = str(a.get("godot_exe", os.getenv("GODOT_BIN", "godot3-bin")))
        host = str(a.get("host", session.proxy.host or "127.0.0.1"))
        port = int(a.get("port", session.proxy.port))
        headless = bool(a.get("headless", False))
        timeout_s = float(a.get("timeout_s", session.proxy.timeout_s))
        return session.reset(
            project_path=project_path,
            godot_exe=godot_exe,
            host=host,
            port=port,
            headless=headless,
            timeout_s=timeout_s,
        )
    if name == "bridge_stop":
        return session.stop_with_status()
    if name == "inspect_node":
        payload: Dict[str, Any] = {"node_path": str(a.get("node_path", ""))}
        for key in ("include_children", "include_visual", "max_depth", "max_children", "probe_fields"):
            if key in a:
                payload[key] = a[key]
        return session.proxy.call("inspect_node", payload)
    if name == "set_property":
        payload: Dict[str, Any] = {
            "node_path": str(a.get("node_path", "")),
            "property": str(a.get("property", a.get("property_path", ""))),
            "value": a.get("value", None),
        }
        if "strict" in a:
            payload["strict"] = bool(a.get("strict"))
        return session.proxy.call("set_property", payload)
    if name == "execute_oys":
        return session.proxy.call("execute_oys", {"script_command": str(a.get("script_command", ""))})
    if name == "capture_vision":
        return session.proxy.call(
            "capture_vision",
            {
                "label": str(a.get("label", "mcp")),
                "include_base64": bool(a.get("include_base64", False)),
            },
        )
    if name == "query_codex_docs":
        out = {
            "topic": str(a.get("topic", "")),
            "max_matches": int(a.get("max_matches", 20)),
        }
        return session.proxy.call("query_codex_docs", out)
    raise ValueError("Unknown tool: %s" % name)


def _jsonrpc_ok(msg_id: Any, result: Dict[str, Any]) -> Dict[str, Any]:
    return {"jsonrpc": "2.0", "id": msg_id, "result": result}


def _jsonrpc_err(msg_id: Any, code: int, message: str) -> Dict[str, Any]:
    return {"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": message}}


def _write_json(msg: Dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(msg, separators=(",", ":"), ensure_ascii=True) + "\n")
    sys.stdout.flush()


def _parse_json_line(line: str) -> Optional[Dict[str, Any]]:
    try:
        msg = json.loads(line)
    except json.JSONDecodeError:
        return None
    if isinstance(msg, dict):
        return msg
    return None


def run_stdio_server(session: BridgeSessionManager) -> int:
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        msg = _parse_json_line(raw)
        if msg is None:
            continue

        msg_id = msg.get("id", None)
        method = str(msg.get("method", ""))
        params = msg.get("params", {})
        if not isinstance(params, dict):
            params = {}

        if method == "initialize":
            client_ver = str(params.get("protocolVersion", "")).strip()
            selected_ver = client_ver if client_ver else MCP_PROTOCOL_VERSION
            result = {
                "protocolVersion": selected_ver,
                "capabilities": {
                    "tools": {},
                    "resources": {},
                },
                "serverInfo": SERVER_INFO,
            }
            _write_json(_jsonrpc_ok(msg_id, result))
            continue

        if method == "notifications/initialized":
            continue

        if method == "ping":
            _write_json(_jsonrpc_ok(msg_id, {}))
            continue

        if method == "tools/list":
            _write_json(_jsonrpc_ok(msg_id, {"tools": TOOL_SCHEMAS}))
            continue

        if method == "tools/call":
            name = str(params.get("name", ""))
            arguments = params.get("arguments", {})
            if not isinstance(arguments, dict):
                arguments = {}
            try:
                result_data = call_tool(session, name, arguments)
                payload = {
                    "content": [{"type": "text", "text": json.dumps(result_data, indent=2, ensure_ascii=True)}],
                    "structuredContent": result_data,
                }
                _write_json(_jsonrpc_ok(msg_id, payload))
            except Exception as exc:  # pylint: disable=broad-except
                payload = {
                    "content": [{"type": "text", "text": str(exc)}],
                    "isError": True,
                }
                _write_json(_jsonrpc_ok(msg_id, payload))
            continue

        if method == "resources/list":
            _write_json(_jsonrpc_ok(msg_id, {"resources": RESOURCE_SCHEMAS}))
            continue

        if method == "resources/read":
            uri = str(params.get("uri", ""))
            try:
                data = call_resource(session, uri, params.get("arguments", {}))
                payload = {
                    "contents": [
                        {
                            "uri": uri,
                            "mimeType": "application/json",
                            "text": json.dumps(data, indent=2, ensure_ascii=True),
                        }
                    ]
                }
                _write_json(_jsonrpc_ok(msg_id, payload))
            except Exception as exc:  # pylint: disable=broad-except
                _write_json(_jsonrpc_err(msg_id, -32000, str(exc)))
            continue

        if msg_id is not None:
            _write_json(_jsonrpc_err(msg_id, -32601, "Method not found: %s" % method))
    return 0


def _load_args_json(raw: str) -> Dict[str, Any]:
    if raw.strip() == "":
        return {}
    parsed = json.loads(raw)
    if not isinstance(parsed, dict):
        raise ValueError("--args-json must decode to an object")
    return parsed


def parse_args(argv: List[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Odisea MCP stdio server and runtime stub")
    parser.add_argument("--host", default=os.getenv("ODISEA_ANNA_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.getenv("ODISEA_ANNA_PORT", "5000")))
    parser.add_argument("--timeout", type=float, default=float(os.getenv("ODISEA_MCP_TIMEOUT", "6.0")))
    parser.add_argument("--tool", help="Direct-call a tool name and print JSON result")
    parser.add_argument("--resource", help="Direct-read a resource URI and print JSON result")
    parser.add_argument("--args-json", default="{}", help="JSON object for tool/resource args")
    return parser.parse_args(argv)


def main(argv: List[str]) -> int:
    try:
        args = parse_args(argv)
        proxy = AnnaRuntimeProxy(host=args.host, port=args.port, timeout_s=max(0.5, float(args.timeout)))
        session = BridgeSessionManager(proxy)

        if args.tool and args.resource:
            print("Use either --tool or --resource, not both.", file=sys.stderr)
            return 2

        payload = _load_args_json(args.args_json)
        if args.tool:
            result = call_tool(session, args.tool, payload)
            print(json.dumps(result, indent=2, ensure_ascii=True))
            return 0
        if args.resource:
            result = call_resource(session, args.resource, payload)
            print(json.dumps(result, indent=2, ensure_ascii=True))
            return 0

        return run_stdio_server(session)
    except Exception as exc:  # pylint: disable=broad-except
        print("odisea-mcp: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
