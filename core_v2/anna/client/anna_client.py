import socket
import json
import time
import random
import os

HOST = '127.0.0.1'
PORT = int(os.getenv("ANNA_PORT", "5000"))

def main():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect((HOST, PORT))
            print(f"Connected to {HOST}:{PORT}")

            # Buffer for receiving data
            buffer = b""

            while True:
                # Read observation (line based)
                while b"\n" not in buffer:
                    chunk = s.recv(4096)
                    if not chunk:
                        print("Connection closed")
                        return
                    buffer += chunk

                line, buffer = buffer.split(b"\n", 1)

                if not line.strip():
                    continue

                try:
                    obs = json.loads(line.decode('utf-8'))
                    # Print summary to avoid flooding console
                    anna = obs.get('anna', {})
                    metrics = obs.get('metrics', {})
                    fps = metrics.get('fps', 0)
                    proximity_count = len(obs.get('proximity', []))
                    frame = anna.get('physics_frame', 0)
                    proto = anna.get('protocol', '?')
                    print(f"[{proto}] frame={frame} | FPS={fps:.1f} | Prox={proximity_count} | Collisions={len(obs.get('collisions', []))}")

                except json.JSONDecodeError:
                    print(f"JSON Decode Error: {line[:50]}...")

                # Decide Action (Random Walk)
                # Apply random movement every few frames or continuously
                move_vec = [
                    random.uniform(-1, 1) if random.random() > 0.5 else 0.0,
                    random.uniform(-1, 1) if random.random() > 0.5 else 0.0
                ]

                look_vec = [
                    random.uniform(-5, 5) if random.random() > 0.7 else 0.0,
                    random.uniform(-2, 2) if random.random() > 0.8 else 0.0
                ]

                action = {
                    "move": move_vec,
                    "look": look_vec,
                    "jump": random.random() > 0.98,
                    "interact": random.random() > 0.99
                }

                # Occasional command injection
                if random.random() > 0.995:
                    action["command"] = "echo Hello from ANNA!"

                # Send Action
                msg = json.dumps(action) + "\n"
                s.sendall(msg.encode('utf-8'))

    except ConnectionRefusedError:
        print(f"Connection refused. Is Godot running with ANNA enabled on port {PORT}?")
    except KeyboardInterrupt:
        print("Stopping client.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
