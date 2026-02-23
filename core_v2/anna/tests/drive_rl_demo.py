import argparse
import json
import os
import socket
import time


def recv_line(sock):
    data = b""
    while b"\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("Socket closed by server.")
        data += chunk
    return json.loads(data.split(b"\n", 1)[0].decode("utf-8"))


def reset_payload(protocol):
    if protocol == "type":
        return {"type": "RESET"}
    return {"command": "RESET"}


def step_payload(protocol, action):
    if protocol == "type":
        return {"type": "STEP", "action": int(action)}
    return {"action": int(action)}


def action_for_step(i):
    # 0=idle, 1=fwd, 2=back, 3=left, 4=right
    phase = i % 120
    if phase < 35:
        return 1
    if phase < 55:
        return 4
    if phase < 90:
        return 1
    if phase < 110:
        return 3
    return 0


def main():
    parser = argparse.ArgumentParser(description="Drive ANNA RL agent to visualize movement.")
    parser.add_argument("--host", default=os.environ.get("ANNA_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("ANNA_PORT", "5000")))
    parser.add_argument(
        "--protocol",
        choices=["command", "type"],
        default=os.environ.get("ANNA_RL_PROTOCOL", "type"),
        help="PR74 style is 'command'; PR75 style is 'type'.",
    )
    parser.add_argument("--steps", type=int, default=600)
    parser.add_argument("--delay", type=float, default=0.03, help="Sleep between steps.")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(6.0)
    print("[drive_rl_demo] Connecting to %s:%d (%s)" % (args.host, args.port, args.protocol))
    sock.connect((args.host, args.port))

    try:
        initial = recv_line(sock)
        if "obs" not in initial:
            raise RuntimeError(
                "Connected to non-RL bridge payload. Start Godot with ANNA_RL_MODE=1 and TestScene_RL.tscn."
            )
        print("[drive_rl_demo] Connected and in RL mode.")

        sock.sendall((json.dumps(reset_payload(args.protocol)) + "\n").encode("utf-8"))
        _ = recv_line(sock)

        for i in range(args.steps):
            action = action_for_step(i)
            sock.sendall((json.dumps(step_payload(args.protocol, action)) + "\n").encode("utf-8"))
            resp = recv_line(sock)
            reward = float(resp.get("reward", 0.0))
            done = bool(resp.get("done", False))

            if i % 30 == 0:
                print("[drive_rl_demo] step=%d action=%d reward=%.3f done=%s" % (i, action, reward, done))

            if done:
                sock.sendall((json.dumps(reset_payload(args.protocol)) + "\n").encode("utf-8"))
                _ = recv_line(sock)

            if args.delay > 0:
                time.sleep(args.delay)

        print("[drive_rl_demo] Done.")
    finally:
        sock.close()


if __name__ == "__main__":
    main()
