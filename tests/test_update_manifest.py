import base64
import json
import os
import subprocess
import tempfile
import pytest
from scripts.update_manifest import calculate_hashes, get_inventory, CHUNK_SIZE

@pytest.fixture
def rsa_keys():
    with tempfile.TemporaryDirectory() as tmpdir:
        private_key = os.path.join(tmpdir, "test.pem")
        public_key = os.path.join(tmpdir, "test.pub.pem")

        # Generate RSA private key
        subprocess.run(["openssl", "genrsa", "-out", private_key, "2048"], check=True)
        # Generate public key
        subprocess.run(["openssl", "rsa", "-in", private_key, "-pubout", "-out", public_key], check=True)

        with open(private_key, "r") as f:
            priv_content = f.read()
        with open(public_key, "r") as f:
            pub_content = f.read()

        yield {
            "dir": tmpdir,
            "private_path": private_key,
            "public_path": public_key,
            "private_content": priv_content,
            "public_content": pub_content
        }

def test_calculate_hashes():
    with tempfile.NamedTemporaryFile(delete=False) as tf:
        # Create a file larger than CHUNK_SIZE (4MiB)
        data = b"0" * (CHUNK_SIZE + 1024)
        tf.write(data)
        tf_path = tf.name

    try:
        hashes = calculate_hashes(tf_path)
        assert hashes["size"] == CHUNK_SIZE + 1024
        assert len(hashes["chunks"]) == 2
        assert hashes["chunks"][0]["size"] == CHUNK_SIZE
        assert hashes["chunks"][1]["size"] == 1024
        assert hashes["chunks"][0]["offset"] == 0
        assert hashes["chunks"][1]["offset"] == CHUNK_SIZE
    finally:
        if os.path.exists(tf_path):
            os.remove(tf_path)

def test_inventory():
    with tempfile.TemporaryDirectory() as tmpdir:
        f1 = os.path.join(tmpdir, "test1.pck")
        with open(f1, "wb") as f:
            f.write(b"content1")

        f2 = os.path.join(tmpdir, "test2.exe")
        with open(f2, "wb") as f:
            f.write(b"content2")

        # Hidden file to skip
        with open(os.path.join(tmpdir, ".hidden"), "wb") as f:
            f.write(b"hidden")

        inventory = get_inventory(tmpdir)
        assert len(inventory) == 2
        paths = [item["path"] for item in inventory]
        assert "test1.pck" in paths
        assert "test2.exe" in paths

def test_full_workflow(rsa_keys):
    with tempfile.TemporaryDirectory() as artifacts_dir:
        artifact_path = os.path.join(artifacts_dir, "Odisea.pck")
        with open(artifact_path, "wb") as f:
            f.write(b"fake pck content")

        manifest_path = os.path.join(artifacts_dir, "manifest.json")

        # 1. Generate
        cmd_gen = [
            "python3", "scripts/update_manifest.py", "generate",
            "--artifacts-dir", artifacts_dir,
            "--output", manifest_path,
            "--key", rsa_keys["private_path"],
            "--key-id", "test",
            "--version", "0.3.3",
            "--build-id", "12345",
            "--channel", "release",
            "--platform", "linux",
            "--arch", "x86_64"
        ]
        subprocess.run(cmd_gen, check=True)

        assert os.path.exists(manifest_path)
        with open(manifest_path, "r") as f:
            envelope = json.load(f)

        assert envelope["schema_version"] == 1
        assert "payload_b64" in envelope
        assert envelope["signatures"][0]["key_id"] == "test"

        # 2. Verify
        # Need to rename public key to match key_id in verify command logic
        pub_key_verify = os.path.join(rsa_keys["dir"], "test.pub.pem")
        # Already named test.pub.pem in fixture if key-id is "test"

        cmd_ver = [
            "python3", "scripts/update_manifest.py", "verify",
            "--manifest", manifest_path,
            "--key-dir", rsa_keys["dir"]
        ]
        result = subprocess.run(cmd_ver, capture_output=True, text=True)
        assert result.returncode == 0
        assert "Manifest verification SUCCESS" in result.stdout

def test_android_apk_is_an_installable_update(rsa_keys):
    with tempfile.TemporaryDirectory() as artifacts_dir:
        artifact_path = os.path.join(artifacts_dir, "Odisea-Android.apk")
        with open(artifact_path, "wb") as f:
            f.write(b"fake apk content")

        manifest_path = os.path.join(artifacts_dir, "manifest.json")
        subprocess.run([
            "python3", "scripts/update_manifest.py", "generate",
            "--artifacts-dir", artifacts_dir,
            "--output", manifest_path,
            "--key", rsa_keys["private_path"],
            "--key-id", "test",
            "--version", "0.3.3",
            "--build-id", "12345",
            "--channel", "nightly",
            "--platform", "android",
            "--arch", "arm64-v8a"
        ], check=True)

        with open(manifest_path, "r") as f:
            envelope = json.load(f)
        payload = json.loads(base64.b64decode(envelope["payload_b64"]).decode("utf-8"))

        assert payload["full_artifact"]["kind"] == "apk"
        assert payload["full_artifact"]["url"].endswith("Odisea-Android.apk")

def test_tampered_payload(rsa_keys):
    with tempfile.TemporaryDirectory() as artifacts_dir:
        artifact_path = os.path.join(artifacts_dir, "Odisea.pck")
        with open(artifact_path, "wb") as f:
            f.write(b"content")

        manifest_path = os.path.join(artifacts_dir, "manifest.json")

        subprocess.run([
            "python3", "scripts/update_manifest.py", "generate",
            "--artifacts-dir", artifacts_dir,
            "--output", manifest_path,
            "--key", rsa_keys["private_path"],
            "--key-id", "test"
        ], check=True)

        # Tamper with the payload
        with open(manifest_path, "r") as f:
            envelope = json.load(f)

        payload_bytes = base64.b64decode(envelope["payload_b64"])
        payload = json.loads(payload_bytes.decode("utf-8"))
        payload["version"] = "9.9.9" # Alter version

        new_payload_json = json.dumps(payload, sort_keys=True, separators=(',', ':'))
        envelope["payload_b64"] = base64.b64encode(new_payload_json.encode("utf-8")).decode("utf-8")

        with open(manifest_path, "w") as f:
            json.dump(envelope, f)

        # Verify should fail
        cmd_ver = [
            "python3", "scripts/update_manifest.py", "verify",
            "--manifest", manifest_path,
            "--key-dir", rsa_keys["dir"]
        ]
        result = subprocess.run(cmd_ver, capture_output=True, text=True)
        assert result.returncode != 0
        assert "Manifest verification FAILED" in result.stderr
