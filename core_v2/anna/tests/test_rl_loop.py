import json
import os
import socket
import sys
import time

HOST = os.environ.get("ANNA_HOST", "127.0.0.1")
PORT = int(os.environ.get("ANNA_PORT", "5000"))
PROTOCOL = os.environ.get("ANNA_RL_PROTOCOL", "command").strip().lower()


def _connect(max_retries=20, retry_delay=0.5):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(6.0)

    for i in range(max_retries):
        try:
            sock.connect((HOST, PORT))
            return sock
        except OSError:
            if i == max_retries - 1:
                raise
            time.sleep(retry_delay)


def _recv_line(sock):
    data = b""
    while b"\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("Socket closed while waiting for newline-delimited payload.")
        data += chunk
    return json.loads(data.split(b"\n", 1)[0].decode("utf-8"))


def _reset_payload():
    if PROTOCOL == "type":
        return {"type": "RESET"}
    return {"command": "RESET"}


def _step_payload(action):
    if PROTOCOL == "type":
        return {"type": "STEP", "action": int(action)}
    return {"action": int(action)}


def _assert_response(name, response):
    if "obs" not in response:
        raise AssertionError(f"{name}: missing 'obs' key. Response={response}")
    if len(response["obs"]) != 12:
        raise AssertionError(f"{name}: expected obs len=12, got len={len(response['obs'])}.")
    if "reward" not in response:
        raise AssertionError(f"{name}: missing 'reward' key. Response={response}")
    if "done" not in response:
        raise AssertionError(f"{name}: missing 'done' key. Response={response}")


def _looks_like_async_observation(response):
    if not isinstance(response, dict):
        return False
    if "obs" in response:
        return False
    return "anna" in response or "collisions" in response or "proximity" in response


def main():
    print(f"[test_rl_loop] Connecting to {HOST}:{PORT} (protocol={PROTOCOL})")
    sock = _connect()
    print("[test_rl_loop] Connected")

    try:
        initial = _recv_line(sock)
        if _looks_like_async_observation(initial):
            raise RuntimeError(
                "Connected to ANNA async mode (non-RL payload). "
                "Launch Godot with ANNA_RL_MODE=1 and a RL scene "
                "(e.g. core_v2/tests/TestScene_RL.tscn)."
            )
        _assert_response("initial", initial)
        print("[test_rl_loop] initial OK")

        sock.sendall((json.dumps(_reset_payload()) + "\n").encode("utf-8"))
        reset = _recv_line(sock)
        _assert_response("reset", reset)
        print("[test_rl_loop] reset OK")

        sock.sendall((json.dumps(_step_payload(1)) + "\n").encode("utf-8"))
        step = _recv_line(sock)
        _assert_response("step", step)
        print(
            "[test_rl_loop] step OK reward=%s done=%s"
            % (step.get("reward"), step.get("done"))
        )
    finally:
        sock.close()

    print("[test_rl_loop] PASS")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"[test_rl_loop] FAIL: {exc}")
        sys.exit(1)
