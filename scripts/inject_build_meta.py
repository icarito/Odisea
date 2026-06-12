#!/usr/bin/env python3
import json
import argparse
import os

def main():
    parser = argparse.ArgumentParser(description="Inject build metadata into JS and JSON files.")
    parser.add_argument("--token", default="")
    parser.add_argument("--commit", required=True)
    parser.add_argument("--build-id", required=True)
    parser.add_argument("--channel", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--official-host", required=True)
    parser.add_argument("--out-js", help="Output path for build_meta.js")
    parser.add_argument("--out-json", help="Output path for build_meta.json")

    args = parser.parse_args()

    meta = {
        "token": args.token,
        "commit": args.commit,
        "build_id": args.build_id,
        "channel": args.channel,
        "version": args.version,
        "officialHost": args.official_host
    }

    if args.out_js:
        os.makedirs(os.path.dirname(args.out_js), exist_ok=True)
        with open(args.out_js, "w") as f:
            f.write(f"window.ODISEA_BUILD_META = {json.dumps(meta, indent=2)};\n")
        print(f"Generated {args.out_js}")

    if args.out_json:
        os.makedirs(os.path.dirname(args.out_json), exist_ok=True)
        with open(args.out_json, "w") as f:
            json.dump(meta, f, indent=2)
        print(f"Generated {args.out_json}")

if __name__ == "__main__":
    main()
