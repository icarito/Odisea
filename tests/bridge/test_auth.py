import asyncio
import aiohttp
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("test_auth")

async def test_auth():
    central_url = "http://localhost:5003/status"

    async with aiohttp.ClientSession() as session:
        logger.info("Testing Central status WITHOUT token...")
        async with session.get(central_url) as resp:
            logger.info(f"Response: {resp.status}")
            assert resp.status == 401

        logger.info("Testing Central status with WRONG token...")
        headers = {"Authorization": "Bearer wrongtoken"}
        async with session.get(central_url, headers=headers) as resp:
            logger.info(f"Response: {resp.status}")
            assert resp.status == 401

        logger.info("Testing Central health (public)...")
        async with session.get("http://localhost:5003/health") as resp:
            logger.info(f"Response: {resp.status}")
            assert resp.status == 200
            data = await resp.json()
            assert data["ok"] is True

        logger.info("Auth verification successful!")

if __name__ == "__main__":
    asyncio.run(test_auth())
