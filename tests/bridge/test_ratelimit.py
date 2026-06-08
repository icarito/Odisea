import asyncio
import aiohttp
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("test_ratelimit")

async def test_ratelimit():
    peer_url = "http://localhost:4999/ws"
    player_id = "ratelimit-player"
    session_id = "ratelimit-session"

    async with aiohttp.ClientSession() as session:
        async with session.ws_connect(peer_url) as ws:
            logger.info("Sending 10 heartbeats very fast...")
            for i in range(10):
                heartbeat = {
                    "type": "heartbeat",
                    "player_id": player_id,
                    "session_id": session_id,
                    "player": {"tick": i},
                    "timestamp": time.time()
                }
                await ws.send_json(heartbeat)

            await asyncio.sleep(1)

            # Peer should have the latest one
            async with session.get("http://localhost:4999/status?player_id=" + player_id) as resp:
                data = await resp.json()
                logger.info(f"Peer latest tick: {data['player']['tick']}")
                assert data['player']['tick'] == 9

            # Central should have dropped most of them.
            # Only 1st one should definitely be there. Maybe one more if lucky with timing.
            # We can check the ghost file count.
            await asyncio.sleep(0.5)

            import os
            path = f"data/ghosts/{player_id}/{session_id}.jsonl"
            if os.path.exists(path):
                with open(path, "r") as f:
                    lines = f.readlines()
                logger.info(f"Ghost file has {len(lines)} lines")
                # Expected: definitely less than 10. Probably 1 or 2.
                assert len(lines) < 10
                assert len(lines) >= 1

        logger.info("Rate limit verification successful!")

if __name__ == "__main__":
    asyncio.run(test_ratelimit())
