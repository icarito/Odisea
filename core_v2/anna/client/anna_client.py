import socket
import json
import time
import os

class AnnaTCPClient:
    def __init__(self, host='127.0.0.1', port=5000):
        self.host = host
        self.port = int(os.getenv("ANNA_PORT", str(port)))
        self.socket = None
        self.buffer = b""

    def connect(self):
        if self.socket:
            self.socket.close()

        retry_count = 0
        while retry_count < 5:
            try:
                self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self.socket.connect((self.host, self.port))
                print(f"[AnnaTCPClient] Connected to {self.host}:{self.port}")
                return
            except ConnectionRefusedError:
                print(f"[AnnaTCPClient] Connection refused. Retrying in 2s... ({retry_count+1}/5)")
                time.sleep(2)
                retry_count += 1

        raise ConnectionError(f"Could not connect to {self.host}:{self.port}")

    def disconnect(self):
        if self.socket:
            self.socket.close()
            self.socket = None
            print("[AnnaTCPClient] Disconnected")

    def send_action(self, action_dict):
        if not self.socket:
            raise ConnectionError("Not connected")

        msg = json.dumps(action_dict) + "\n"
        try:
            self.socket.sendall(msg.encode('utf-8'))
        except BrokenPipeError:
            print("[AnnaTCPClient] Broken pipe, reconnecting...")
            self.connect()
            self.socket.sendall(msg.encode('utf-8'))

    def receive_state(self):
        if not self.socket:
            raise ConnectionError("Not connected")

        while b"\n" not in self.buffer:
            try:
                chunk = self.socket.recv(4096)
                if not chunk:
                    raise ConnectionError("Server closed connection")
                self.buffer += chunk
            except (ConnectionResetError, ConnectionAbortedError):
                 print("[AnnaTCPClient] Connection reset, reconnecting...")
                 self.connect()
                 return self.receive_state()

        line, self.buffer = self.buffer.split(b"\n", 1)

        if not line.strip():
            return self.receive_state()

        try:
            return json.loads(line.decode('utf-8'))
        except json.JSONDecodeError as e:
            print(f"[AnnaTCPClient] JSON Error: {e}")
            return {}

# Example usage (preserving original functionality if run as script)
if __name__ == "__main__":
    import random
    client = AnnaTCPClient()
    try:
        client.connect()
        while True:
            obs = client.receive_state()
            print(f"Frame: {obs.get('anna', {}).get('physics_frame', '?')}")

            action = {
                "move": [random.uniform(-1, 1), random.uniform(-1, 1)],
                "look": [random.uniform(-5, 5), random.uniform(-2, 2)]
            }
            client.send_action(action)

    except KeyboardInterrupt:
        client.disconnect()
    except Exception as e:
        print(f"Error: {e}")
