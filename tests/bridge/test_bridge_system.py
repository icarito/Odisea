import asyncio
import json
import logging
import aiohttp
import time
import uuid

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("test_client")

async def run_test():
    peer_url = "http://localhost:4999/ws"
    player_id = "test-player-" + str(uuid.uuid4())[:8]
    session_id = "test-session-" + str(uuid.uuid4())[:8]

    logger.info(f"Starting test client for player {player_id}, session {session_id}")

    async with aiohttp.ClientSession() as session:
        try:
            async with session.ws_connect(peer_url) as ws:
                logger.info(f"Connected to Peer at {peer_url}")

                for i in range(10):
                    heartbeat = {
                        "schema_version": 1,
                        "type": "heartbeat",
                        "player_id": player_id,
                        "session_id": session_id,
                        "host": "test-host",
                        "godot_version": "3.6.2",
                        "game_version": "0.1.0",
                        "platform": "desktop",
                        "player": {
                            "position": [12.5, 1.2, -3.8 + i*0.1],
                            "velocity": [0.1, 0.0, 0.0],
                            "yaw": 1.57,
                            "pitch": -0.1,
                            "roll": 0.0,
                            "mode": "standard",
                            "scene": "Dome_Crio",
                            "zone": "criogenia",
                            "tick": 1423 + i,
                            "fps": 60.0,
                            "memory_mb": 150.0
                        },
                        "timestamp": time.time()
                    }

                    logger.info(f"Sending heartbeat {i}...")
                    await ws.send_json(heartbeat)
                    await asyncio.sleep(0.1) # 100ms interval

                logger.info("Sent 10 heartbeats. Waiting a bit for relay...")
                await asyncio.sleep(2)

                # Check Peer status
                async with session.get("http://localhost:4999/status") as resp:
                    status = await resp.json()
                    logger.info(f"Peer status: {status}")
                    assert player_id in status

                # Check Central status
                headers = {"Authorization": "Bearer mysecret"}
                async with session.get("http://localhost:5003/status", headers=headers) as resp:
                    status = await resp.json()
                    logger.info(f"Central status: {status}")
                    assert player_id in status

                logger.info("Verification successful!")

        except Exception as e:
            logger.error(f"Test failed: {e}")

if __name__ == "__main__":
    asyncio.run(run_test())
