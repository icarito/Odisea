#!/usr/bin/env python3
import json
import argparse
import os
import sys

CANARY_TOKEN = "ODISEA_TOKEN_CANARY_MISSING"
CANARY_COMMIT = "unknown-commit"
CANARY_BUILD_ID = "local-canary"
CANARY_CHANNEL = "dev"
CANARY_VERSION = "0.1.0-canary"
CANARY_OFFICIAL_HOST = "odisea.educa.juegos"

def _value_or_canary(value, canary):
    if value is None:
        return canary
    if str(value).strip() == "":
        return canary
    return value

def _ensure_parent(path):
    parent = os.path.dirname(path)
    if parent != "":
        os.makedirs(parent, exist_ok=True)

def main():
    parser = argparse.ArgumentParser(description="Inject build metadata into JS and JSON files.")
    parser.add_argument("--token", nargs="?", default=CANARY_TOKEN, const=CANARY_TOKEN)
    parser.add_argument("--commit", nargs="?", default=CANARY_COMMIT, const=CANARY_COMMIT)
    parser.add_argument("--build-id", nargs="?", default=CANARY_BUILD_ID, const=CANARY_BUILD_ID)
    parser.add_argument("--channel", nargs="?", default=CANARY_CHANNEL, const=CANARY_CHANNEL)
    parser.add_argument("--version", nargs="?", default=CANARY_VERSION, const=CANARY_VERSION)
    parser.add_argument("--official-host", nargs="?", default=CANARY_OFFICIAL_HOST, const=CANARY_OFFICIAL_HOST)
    parser.add_argument("--out-js", help="Output path for build_meta.js")
    parser.add_argument("--out-json", help="Output path for build_meta.json")

    args = parser.parse_args()

    meta = {
        "token": _value_or_canary(args.token, CANARY_TOKEN),
        "commit": _value_or_canary(args.commit, CANARY_COMMIT),
        "build_id": _value_or_canary(args.build_id, CANARY_BUILD_ID),
        "channel": _value_or_canary(args.channel, CANARY_CHANNEL),
        "version": _value_or_canary(args.version, CANARY_VERSION),
        "officialHost": _value_or_canary(args.official_host, CANARY_OFFICIAL_HOST)
    }

    for key, value in meta.items():
        if "canary" in value.lower() or value.startswith("unknown-"):
            print(f"Warning: build metadata {key} is using placeholder value {value}", file=sys.stderr)

    if args.out_js:
        _ensure_parent(args.out_js)
        with open(args.out_js, "w") as f:
            f.write(f"window.ODISEA_BUILD_META = {json.dumps(meta, indent=2)};\n")
        print(f"Generated {args.out_js}")

    if args.out_json:
        _ensure_parent(args.out_json)
        with open(args.out_json, "w") as f:
            json.dump(meta, f, indent=2)
        print(f"Generated {args.out_json}")

if __name__ == "__main__":
    main()
