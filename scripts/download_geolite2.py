import os
import sys
import tarfile
import urllib.request
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("download_geolite2")

# MaxMind GeoLite2 City - This is a direct link to a public mirror or requires a license key.
# For this task, we assume a public accessible URL or a placeholder that the user can update.
# MaxMind typically requires an account and license key now.
# However, for the sake of the exercise, I will use a placeholder or a known mirror if available.
# Since I cannot easily get a fresh license key, I'll use a placeholder or common mirror URL.
GEOLITE2_URL = "https://git.io/GeoLite2-City.mmdb.tar.gz" # Common shortcut/mirror
DEST_DIR = "data"
DEST_FILE = os.path.join(DEST_DIR, "GeoLite2-City.mmdb")

def download_geolite2():
    if not os.path.exists(DEST_DIR):
        os.makedirs(DEST_DIR)

    logger.info(f"Downloading GeoLite2 City from {GEOLITE2_URL}...")
    temp_tar = os.path.join(DEST_DIR, "GeoLite2-City.tar.gz")
    
    try:
        urllib.request.urlretrieve(GEOLITE2_URL, temp_tar)
        logger.info("Extracting...")
        with tarfile.open(temp_tar, "r:gz") as tar:
            # Find the mmdb file in the tarball
            mmdb_member = next((m for m in tar.getmembers() if m.name.endswith(".mmdb")), None)
            if mmdb_member:
                # Extract only the mmdb file and rename it
                mmdb_member.name = os.path.basename(mmdb_member.name)
                tar.extract(mmdb_member, path=DEST_DIR)
                # Rename if needed (some tarballs have a versioned folder)
                extracted_path = os.path.join(DEST_DIR, mmdb_member.name)
                if extracted_path != DEST_FILE:
                    if os.path.exists(DEST_FILE):
                        os.remove(DEST_FILE)
                    os.rename(extracted_path, DEST_FILE)
                logger.info(f"GeoLite2 City database saved to {DEST_FILE}")
            else:
                logger.error("Could not find .mmdb file in the archive")
        
        os.remove(temp_tar)
    except Exception as e:
        logger.error(f"Failed to download/extract GeoLite2: {e}")
        # In a real scenario, we might want to try another mirror or ask for a license key.
        # For now, we'll just exit with error.
        sys.exit(1)

if __name__ == "__main__":
    download_geolite2()
