#!/usr/bin/env python3
import argparse
import json
import os
import socket
import sys
import time


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Deterministic ANNA TCP driver for visual OYS test")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=int(os.getenv("ANNA_PORT", "5000")))
    parser.add_argument("--frames", type=int, default=72, help="Number of observation/action frames to run")
    parser.add_argument("--move-x", type=float, default=0.0)
    parser.add_argument("--move-y", type=float, default=-1.0)
    parser.add_argument("--look-x", type=float, default=4.0)
    parser.add_argument("--look-y", type=float, default=0.0)
    parser.add_argument("--connect-timeout", type=float, default=2.5)
    parser.add_argument("--step-timeout", type=float, default=2.5)
    parser.add_argument("--retries", type=int, default=60)
    parser.add_argument("--retry-delay", type=float, default=0.05)
    parser.add_argument("--max-runtime", type=float, default=8.0, help="Hard timeout in seconds for entire driver")
    return parser.parse_args()


def read_line(sock: socket.socket, buffer: bytes, timeout: float) -> tuple[str | None, bytes]:
    deadline = time.time() + timeout
    while True:
        if b"\n" in buffer:
            line_raw, buffer = buffer.split(b"\n", 1)
            return line_raw.decode("utf-8", errors="replace").strip(), buffer

        remaining = deadline - time.time()
        if remaining <= 0.0:
            return None, buffer

        sock.settimeout(remaining)
        chunk = sock.recv(4096)
        if not chunk:
            return None, buffer
        buffer += chunk


def main() -> int:
    args = parse_args()
    start_time = time.time()

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    connected = False

    for attempt in range(args.retries):
        if (time.time() - start_time) > args.max_runtime:
            print("[ANNA_TEST_DRIVER] max runtime reached before connect")
            return 4
        try:
            sock.settimeout(args.connect_timeout)
            sock.connect((args.host, args.port))
            connected = True
            break
        except OSError:
            if attempt == args.retries - 1:
                break
            time.sleep(args.retry_delay)

    if not connected:
        print(f"[ANNA_TEST_DRIVER] could not connect to {args.host}:{args.port}")
        return 2

    buffer = b""
    frames_sent = 0

    try:
        while frames_sent < args.frames:
            if (time.time() - start_time) > args.max_runtime:
                print("[ANNA_TEST_DRIVER] max runtime reached while stepping")
                return 4
            line, buffer = read_line(sock, buffer, args.step_timeout)
            if line is None:
                print("[ANNA_TEST_DRIVER] timeout or closed connection while waiting for observation")
                return 3

            try:
                _obs = json.loads(line)
            except json.JSONDecodeError:
                # Keep test deterministic: ignore malformed packet and continue loop.
                continue

            action = {
                "move": [float(args.move_x), float(args.move_y)],
                "look": [float(args.look_x), float(args.look_y)],
                "jump": False,
                "interact": False,
                "sprint": False,
                "crouch": False,
            }
            sock.sendall((json.dumps(action) + "\n").encode("utf-8"))
            frames_sent += 1

        # Send a final neutral action to reduce state carry-over between runs.
        neutral = {
            "move": [0.0, 0.0],
            "look": [0.0, 0.0],
            "jump": False,
            "interact": False,
            "sprint": False,
            "crouch": False,
        }
        sock.sendall((json.dumps(neutral) + "\n").encode("utf-8"))
        print(f"[ANNA_TEST_DRIVER] completed frames={frames_sent}")
        return 0
    finally:
        try:
            sock.close()
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
