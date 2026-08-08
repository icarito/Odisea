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

    # Elegir el artefacto del update. PREFERIR el .pck.gz (comprimido): el .pck no
    # está comprimido internamente y gzip ahorra ~71%; gzip+Range son incompatibles,
    # así que servimos un .gz pre-comprimido que el cliente baja por chunks y
    # descomprime. Luego .pck crudo (hot-swap directo). Si no hay (móvil/web), el más
    # grande (.zip/.apk).
    compression = "none"
    uncompressed_sha256 = ""
    uncompressed_size = 0
    pck_gz = [a for a in artifacts if a["path"].endswith(".pck.gz")]
    pcks = [a for a in artifacts if a["path"].endswith(".pck")]
    if pck_gz:
        pck_gz.sort(key=lambda x: x["size"], reverse=True)
        main_artifact = pck_gz[0]
        compression = "gzip"
        # sha256/size del .pck DESCOMPRIMIDO, para verificar tras inflar en el cliente.
        import gzip as _gz
        h = hashlib.sha256()
        n = 0
        with _gz.open(os.path.join(args.artifacts_dir, main_artifact["path"]), "rb") as gf:
            while True:
                b = gf.read(1024 * 1024)
                if not b:
                    break
                h.update(b)
                n += len(b)
        uncompressed_sha256 = h.hexdigest()
        uncompressed_size = n
    elif pcks:
        pcks.sort(key=lambda x: x["size"], reverse=True)
        main_artifact = pcks[0]
    else:
        artifacts.sort(key=lambda x: x["size"], reverse=True)
        main_artifact = artifacts[0]

    # project.godot hash
    project_godot_hash = ""
    if args.project_godot:
        with open(args.project_godot, "rb") as f:
            project_godot_hash = hashlib.sha256(f.read()).hexdigest()

    # Values from args or defaults
    version = args.version or "0.0.0"
    build_id = args.build_id or "0"
    channel = args.channel or "dev"
    platform = args.platform or "linux"
    arch = args.arch or "x86_64"
    commit = args.commit or "0" * 40

    # Binary artifact
    binary_full_artifact = None
    if args.binary_path:
        binary_hashes = calculate_hashes(args.binary_path)
        binary_rel_path = os.path.relpath(args.binary_path, args.artifacts_dir)
        binary_full_artifact = {
            "artifact_id": f"{platform}-{arch}-{version}-binary-full",
            "kind": "binary",
            "url": f"{args.base_url}/{binary_rel_path}" if args.base_url else binary_rel_path,
            "size": binary_hashes["size"],
            "sha256": binary_hashes["sha256"],
            "chunk_size": binary_hashes["chunk_size"],
            "chunks": binary_hashes["chunks"]
        }

    # release_notes_url debe apuntar al TAG REAL del release, derivado del base_url
    # (que ya tiene .../releases/download/<TAG>). Antes se hardcodeaba v{version} con
    # la versión humana (espacios/paréntesis) -> link de changelog roto.
    release_notes_url = f"https://github.com/icarito/Odisea/releases/tag/v{version}"
    if args.base_url and "/releases/download/" in args.base_url:
        release_tag = args.base_url.split("/releases/download/", 1)[1].split("/", 1)[0]
        if release_tag:
            release_notes_url = f"https://github.com/icarito/Odisea/releases/tag/{release_tag}"

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
        "project_godot_hash": project_godot_hash,
        "binary_full_artifact": binary_full_artifact,
        "binary_delta_artifacts": [],
        "full_artifact": {
            "artifact_id": f"{platform}-{arch}-{version}-full",
            "kind": (
                "apk" if main_artifact["path"].endswith(".apk")
                else "full_pck" if ".pck" in main_artifact["path"]
                else "archive"
            ),
            "url": f"{args.base_url}/{main_artifact['path']}" if args.base_url else main_artifact["path"],
            # size/sha256/chunks describen el archivo TAL CUAL se transporta (el .gz si
            # está comprimido), para Range/resume. uncompressed_* verifican el .pck
            # final tras descomprimir.
            "compression": compression,
            "size": main_artifact["size"],
            "sha256": main_artifact["sha256"],
            "uncompressed_size": uncompressed_size,
            "uncompressed_sha256": uncompressed_sha256,
            "chunk_size": main_artifact["chunk_size"],
            "chunks": main_artifact["chunks"]
        },
        "delta_artifacts": [],
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

def _process_patch(gz_path, base_url, artifact_id, from_build_id, target_uncompressed_size, target_uncompressed_sha256):
    gz_hashes = calculate_hashes(gz_path)
    import gzip as _gz
    h = hashlib.sha256()
    patch_raw_size = 0
    with _gz.open(gz_path, "rb") as gf:
        while True:
            b = gf.read(1024 * 1024)
            if not b:
                break
            h.update(b)
            patch_raw_size += len(b)
    patch_raw_sha256 = h.hexdigest()

    gz_name = os.path.basename(gz_path)
    return {
        "artifact_id": artifact_id,
        "kind": "delta_patch",
        "from_build_id": str(from_build_id),
        "url": f"{base_url}/{gz_name}" if base_url else gz_name,
        "compression": "gzip",
        "size": gz_hashes["size"],
        "sha256": gz_hashes["sha256"],
        "chunk_size": gz_hashes["chunk_size"],
        "chunks": gz_hashes["chunks"],
        "patch_uncompressed_size": patch_raw_size,
        "patch_sha256": patch_raw_sha256,
        "uncompressed_size": target_uncompressed_size,
        "uncompressed_sha256": target_uncompressed_sha256,
    }

def cmd_add_delta(args):
    """Inyecta un delta_artifact (patch bsdiff) en un manifest ya generado y lo
    re-firma. El cliente elige el delta cuyo from_build_id == su build actual;
    si no hay match, cae al full_artifact. NO se encadenan: cada delta reconstruye
    el .pck nuevo COMPLETO directo desde el build viejo indicado."""
    with open(args.manifest, "r") as f:
        envelope = json.load(f)
    payload = json.loads(base64.b64decode(envelope["payload_b64"]))

    platform = payload["platform"]
    arch = payload["arch"]
    version = payload["version"]

    if args.patch_gz:
        delta = _process_patch(
            args.patch_gz, args.base_url,
            f"{platform}-{arch}-{version}-delta-from-{args.from_build_id}",
            args.from_build_id,
            payload["full_artifact"].get("uncompressed_size", 0),
            payload["full_artifact"].get("uncompressed_sha256", "")
        )
        payload.setdefault("delta_artifacts", [])
        payload["delta_artifacts"] = [
            d for d in payload["delta_artifacts"]
            if d.get("from_build_id") != delta["from_build_id"]
        ]
        payload["delta_artifacts"].append(delta)

    if args.binary_patch_gz:
        if not payload.get("binary_full_artifact"):
            print("Error: Cannot add binary delta to manifest without binary_full_artifact", file=sys.stderr)
            sys.exit(1)

        b_delta = _process_patch(
            args.binary_patch_gz, args.base_url,
            f"{platform}-{arch}-{version}-binary-delta-from-{args.from_build_id}",
            args.from_build_id,
            payload["binary_full_artifact"].get("size", 0),
            payload["binary_full_artifact"].get("sha256", "")
        )
        payload.setdefault("binary_delta_artifacts", [])
        payload["binary_delta_artifacts"] = [
            d for d in payload["binary_delta_artifacts"]
            if d.get("from_build_id") != b_delta["from_build_id"]
        ]
        payload["binary_delta_artifacts"].append(b_delta)

    # Re-serializar y RE-FIRMAR (la firma cubre el payload, que cambió).
    payload_json = json.dumps(payload, sort_keys=True, separators=(',', ':'))
    payload_bytes = payload_json.encode("utf-8")
    if os.path.exists(args.key):
        with open(args.key, "r") as f:
            key_content = f.read()
    else:
        key_content = args.key
    signature_raw = sign_payload(payload_bytes, key_content)

    envelope = {
        "schema_version": 1,
        "payload_b64": base64.b64encode(payload_bytes).decode("utf-8"),
        "signatures": [{
            "algorithm": "RSASSA-PKCS1-v1_5-SHA256",
            "key_id": args.key_id,
            "value_b64": base64.b64encode(signature_raw).decode("utf-8"),
        }],
    }
    out = args.output or args.manifest
    with open(out, "w") as f:
        f.write(json.dumps(envelope, indent=2))
    print(f"Manifest updated and re-signed: {out}")

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
    p_gen.add_argument("--project-godot", help="Path to project.godot to hash")
    p_gen.add_argument("--binary-path", help="Path to the platform binary")

    # Add-delta: inyecta un patch bsdiff en un manifest ya generado y lo re-firma.
    p_delta = subparsers.add_parser("add-delta")
    p_delta.add_argument("--manifest", required=True, help="Manifest generado a modificar")
    p_delta.add_argument("--patch-gz", help=".patch.gz a publicar como delta")
    p_delta.add_argument("--binary-patch-gz", help="Binary .patch.gz a publicar como delta")
    p_delta.add_argument("--from-build-id", required=True, help="build_id del .pck base del diff")
    p_delta.add_argument("--key", required=True, help="Path a private.pem o su contenido")
    p_delta.add_argument("--key-id", required=True)
    p_delta.add_argument("--base-url", help="Base URL de descarga del patch")
    p_delta.add_argument("--output", help="Salida (default: sobrescribe --manifest)")

    # Verify
    p_ver = subparsers.add_parser("verify")
    p_ver.add_argument("--manifest", required=True)
    p_ver.add_argument("--key-dir", required=True)

    args = parser.parse_args()

    if args.command == "inventory":
        cmd_inventory(args)
    elif args.command == "generate":
        cmd_generate(args)
    elif args.command == "add-delta":
        cmd_add_delta(args)
    elif args.command == "verify":
        cmd_verify(args)

if __name__ == "__main__":
    main()
