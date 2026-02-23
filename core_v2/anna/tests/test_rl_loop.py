import socket
import json
import time
import sys

HOST = '127.0.0.1'
PORT = 5000

def main():
    print(f"Connecting to {HOST}:{PORT}...")
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

    # Retry connection
    connected = False
    for i in range(10):
        try:
            s.connect((HOST, PORT))
            connected = True
            break
        except ConnectionRefusedError:
            print(f"Connection refused, retrying ({i+1}/10)...")
            time.sleep(1)

    if not connected:
        print("Failed to connect.")
        sys.exit(1)

    print("Connected!")

    # 1. Send RESET
    print("Sending RESET...")
    s.sendall(b'{"type": "RESET"}\n')

    # Read response
    data = s.recv(4096).decode('utf-8')
    print(f"Received RESET response: {data.strip()}")
    try:
        resp = json.loads(data)
        if "obs" not in resp:
            print("FAILED: No 'obs' in RESET response")
            sys.exit(1)
        if len(resp["obs"]) != 12:
            print(f"FAILED: Obs length is {len(resp['obs'])}, expected 12")
            sys.exit(1)
    except json.JSONDecodeError:
        print("FAILED: Invalid JSON")
        sys.exit(1)

    # 2. Send STEP
    print("Sending STEP...")
    s.sendall(b'{"type": "STEP", "action": 1}\n')

    data = s.recv(4096).decode('utf-8')
    print(f"Received STEP response: {data.strip()}")
    try:
        resp = json.loads(data)
        if "reward" not in resp:
            print("FAILED: No 'reward' in STEP response")
            sys.exit(1)
    except json.JSONDecodeError:
        print("FAILED: Invalid JSON")
        sys.exit(1)

    print("Test PASSED")
    s.close()

if __name__ == "__main__":
    main()
