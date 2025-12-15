import socket
import json
import time

class UDPSender:
    def __init__(self, host='127.0.0.1', port=5555):
        self.host = host
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.last_send_time = 0
        self.target_fps = 60
        self.frame_interval = 1.0 / self.target_fps

    def send_pose(self, pose_data):
        current_time = time.time()
        if current_time - self.last_send_time < self.frame_interval:
            return  # Skip to maintain 60Hz

        try:
            json_data = json.dumps(pose_data, separators=(',', ':'))
            self.sock.sendto(json_data.encode('utf-8'), (self.host, self.port))
            self.last_send_time = current_time
        except Exception as e:
            print(f"UDP send error: {e}")

    def close(self):
        self.sock.close()