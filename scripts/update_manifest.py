#!/usr/bin/env python3
import argparse
import base64
import datetime
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from typing import List, Dict, Any, Optional

CHUNK_SIZE = 4 * 1024 * 1024  # 4 MiB

def calculate_hashes(filepath: str) -> Dict[str, Any]:
    sha256_full = hashlib.sha256()
    chunks = []
    size = os.path.getsize(filepath)

    with open(filepath, "rb") as f:
        index = 0
        while True:
            chunk_data = f.read(CHUNK_SIZE)
            if not chunk_data:
                break

            chunk_sha256 = hashlib.sha256(chunk_data).hexdigest()
            chunks.append({
                "index": index,
                "offset": index * CHUNK_SIZE,
                "size": len(chunk_data),
                "sha256": chunk_sha256
            })

            sha256_full.update(chunk_data)
            index += 1

    return {
        "size": size,
        "sha256": sha256_full.hexdigest(),
        "chunk_size": CHUNK_SIZE,
        "chunks": chunks
    }

def get_inventory(artifacts_dir: str) -> List[Dict[str, Any]]:
    inventory = []
    for root, _, files in os.walk(artifacts_dir):
        for file in files:
            # Skip hidden files and manifests themselves
            if file.startswith(".") or file.startswith("manifest-"):
                continue

            path = os.path.join(root, file)
            rel_path = os.path.relpath(path, artifacts_dir)
            hashes = calculate_hashes(path)

            inventory.append({
                "path": rel_path,
                **hashes
            })
    return inventory

def sign_payload(payload_bytes: bytes, key_content: str) -> bytes:
    # Use openssl dgst -sha256 -sign
    # The private key is passed via stdin to avoid writing it to disk.
    with tempfile.NamedTemporaryFile(delete=False) as tf:
        tf.write(payload_bytes)
        payload_temp = tf.name

    try:
        # openssl dgst -sha256 -sign <key> <file>
        # Using /dev/stdin for the key
        cmd = ["openssl", "dgst", "-sha256", "-sign", "/dev/stdin", payload_temp]
        result = subprocess.run(cmd, input=key_content.encode("utf-8"), capture_output=True, check=True)
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error signing payload: {e.stderr.decode()}", file=sys.stderr)
        raise
    finally:
        if os.path.exists(payload_temp):
            os.remove(payload_temp)

def verify_signature(payload_bytes: bytes, signature_bytes: bytes, public_key_path: str) -> bool:
    with tempfile.NamedTemporaryFile(delete=False) as tf_payload, \
         tempfile.NamedTemporaryFile(delete=False) as tf_sig:
        tf_payload.write(payload_bytes)
        tf_sig.write(signature_bytes)
        payload_temp = tf_payload.name
        sig_temp = tf_sig.name

    try:
        cmd = ["openssl", "dgst", "-sha256", "-verify", public_key_path, "-signature", sig_temp, payload_temp]
        result = subprocess.run(cmd, capture_output=True)
        return result.returncode == 0
    finally:
        for f in [payload_temp, sig_temp]:
            if os.path.exists(f):
                os.remove(f)

def cmd_inventory(args):
    inventory = get_inventory(args.artifacts_dir)
    output = json.dumps(inventory, indent=2)
    if args.output:
        with open(args.output, "w") as f:
            f.write(output)
        print(f"Inventory written to {args.output}")
    else:
        print(output)

def cmd_generate(args):
    # This is a bit simplified, in CI we'd pass more metadata via env/args
    # Re-using logic from inject_build_meta.py where possible or requested fields

    # Locate full artifact (usually .pck or .zip/.apk depending on platform)
    artifacts = get_inventory(args.artifacts_dir)
    if not artifacts:
        print(f"Error: No artifacts found in {args.artifacts_dir}", file=sys.stderr)
        sys.exit(1)

    # Heuristic for full_artifact: largest file or first one if only one
    artifacts.sort(key=lambda x: x["size"], reverse=True)
    main_artifact = artifacts[0]

    # Values from args or defaults
    version = args.version or "0.0.0"
    build_id = args.build_id or "0"
    channel = args.channel or "dev"

    # release_notes_url debe apuntar al TAG REAL del release, derivado del base_url
    # (que ya tiene .../releases/download/<TAG>). Antes se hardcodeaba v{version} con
    # la versión humana (espacios/paréntesis) -> link de changelog roto.
    release_notes_url = f"https://github.com/icarito/Odisea/releases/tag/v{version}"
    if args.base_url and "/releases/download/" in args.base_url:
        release_tag = args.base_url.split("/releases/download/", 1)[1].split("/", 1)[0]
        if release_tag:
            release_notes_url = f"https://github.com/icarito/Odisea/releases/tag/{release_tag}"
    platform = args.platform or "linux"
    arch = args.arch or "x86_64"
    commit = args.commit or "0" * 40

    issued_at = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
    # Expire in 30 days by default
    expires_at = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=30)).isoformat().replace("+00:00", "Z")

    payload = {
        "manifest_id": f"{channel}-{version}-{build_id}",
        "channel": channel,
        "version": version,
        "build_id": build_id,
        "release_sequence": int(build_id) if build_id.isdigit() else 0,
        "commit": commit,
        "issued_at": issued_at,
        "expires_at": expires_at,
        "severity": "optional",
        "min_supported_version": args.min_supported_version or "0.0.0",
        "force_full": False,
        "rollout_percent": 100,
        "platform": platform,
        "arch": arch,
        "full_artifact": {
            "artifact_id": f"{platform}-{arch}-{version}-full",
            "kind": "full_pck" if main_artifact["path"].endswith(".pck") else "archive",
            "url": f"{args.base_url}/{main_artifact['path']}" if args.base_url else main_artifact["path"],
            "size": main_artifact["size"],
            "sha256": main_artifact["sha256"],
            "chunk_size": main_artifact["chunk_size"],
            "chunks": main_artifact["chunks"]
        },
        "deltas": [],
        "release_notes_url": release_notes_url,
        "downloads_page": "https://icarito.github.io/odisea-neon-dreams/#downloads"
    }

    payload_json = json.dumps(payload, sort_keys=True, separators=(',', ':'))
    payload_bytes = payload_json.encode("utf-8")

    # Handle private key (can be path or content)
    if os.path.exists(args.key):
        with open(args.key, "r") as f:
            key_content = f.read()
    else:
        key_content = args.key

    signature_raw = sign_payload(payload_bytes, key_content)

    envelope = {
        "schema_version": 1,
        "payload_b64": base64.b64encode(payload_bytes).decode("utf-8"),
        "signatures": [
            {
                "algorithm": "RSASSA-PKCS1-v1_5-SHA256",
                "key_id": args.key_id or "release-key",
                "value_b64": base64.b64encode(signature_raw).decode("utf-8")
            }
        ]
    }

    output = json.dumps(envelope, indent=2)
    if args.output:
        with open(args.output, "w") as f:
            f.write(output)
        print(f"Manifest written to {args.output}")
    else:
        print(output)

def cmd_verify(args):
    with open(args.manifest, "r") as f:
        envelope = json.load(f)

    payload_b64 = envelope.get("payload_b64")
    if not payload_b64:
        print("Error: Missing payload_b64", file=sys.stderr)
        sys.exit(1)

    payload_bytes = base64.b64decode(payload_b64)

    success = False
    for sig in envelope.get("signatures", []):
        if sig.get("algorithm") != "RSASSA-PKCS1-v1_5-SHA256":
            continue

        key_id = sig.get("key_id")
        key_path = os.path.join(args.key_dir, f"{key_id}.pub.pem")
        if not os.path.exists(key_path):
            print(f"Warning: Public key not found for {key_id} at {key_path}", file=sys.stderr)
            continue

        signature_bytes = base64.b64decode(sig.get("value_b64"))
        if verify_signature(payload_bytes, signature_bytes, key_path):
            print(f"Verified signature with key {key_id}")
            success = True
            break

    if success:
        print("Manifest verification SUCCESS")
        # Print payload for convenience?
        # print(payload_bytes.decode("utf-8"))
    else:
        print("Manifest verification FAILED", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Odisea Update Manifest Tool")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Inventory
    p_inv = subparsers.add_parser("inventory")
    p_inv.add_argument("--artifacts-dir", required=True)
    p_inv.add_argument("--output")

    # Generate
    p_gen = subparsers.add_parser("generate")
    p_gen.add_argument("--artifacts-dir", required=True)
    p_gen.add_argument("--output")
    p_gen.add_argument("--key", required=True, help="Path to private.pem or its content")
    p_gen.add_argument("--key-id", required=True)
    p_gen.add_argument("--version")
    p_gen.add_argument("--build-id")
    p_gen.add_argument("--channel")
    p_gen.add_argument("--platform")
    p_gen.add_argument("--arch")
    p_gen.add_argument("--commit")
    p_gen.add_argument("--min-supported-version")
    p_gen.add_argument("--base-url", help="Base URL for artifacts")

    # Verify
    p_ver = subparsers.add_parser("verify")
    p_ver.add_argument("--manifest", required=True)
    p_ver.add_argument("--key-dir", required=True)

    args = parser.parse_args()

    if args.command == "inventory":
        cmd_inventory(args)
    elif args.command == "generate":
        cmd_generate(args)
    elif args.command == "verify":
        cmd_verify(args)

if __name__ == "__main__":
    main()
