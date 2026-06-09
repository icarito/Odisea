import asyncio
import json
import time
import websockets
import random

async def mock_peer():
    uri = "ws://localhost:5003/ws"
    try:
        async with websockets.connect(uri) as websocket:
            # Handshake
            await websocket.send(json.dumps({
                "type": "handshake",
                "token": "secret-token",
                "peer_id": "mock-peer-1"
            }))

            ack = await websocket.recv()
            print(f"Handshake ack: {ack}")

            player_id = "mock-player-123"
            session_id = "mock-session-456"

            t = 0
            while True:
                t += 1
                # Spiral motion
                angle = t * 0.1
                r = 10
                x = r * math.cos(angle)
                z = r * math.sin(angle)
                y = 1 + 0.05 * t

                heartbeat = {
                    "type": "heartbeat",
                    "player_id": player_id,
                    "session_id": session_id,
                    "host": "MockHost",
                    "platform": "Linux",
                    "godot_version": "3.6.2-stable",
                    "game_version": "0.1.0",
                    "player": {
                        "position": [x, y, z],
                        "velocity": [0.1, 0.0, 0.1],
                        "yaw": -angle,
                        "pitch": 0.0,
                        "roll": 0.0,
                        "mode": "standard",
                        "scene": "Dome_Crio",
                        "zone": "Alpha",
                        "tick": t,
                        "fps": 60 + random.uniform(-2, 2),
                        "memory_mb": 80 + 0.05 * t
                    },
                    "timestamp": time.time()
                }

                await websocket.send(json.dumps(heartbeat))
                await asyncio.sleep(0.5)
    except Exception as e:
        print(f"Mock peer error: {e}")

if __name__ == "__main__":
    import math
    try:
        asyncio.run(mock_peer())
    except KeyboardInterrupt:
        pass
