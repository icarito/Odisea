#!/usr/bin/env python3
"""Backfill coarse geo stats from nginx access logs into a SQLite DB.

This intentionally stores hashed IPs plus city/country aggregates, not raw IPs.
"""

import collections
import datetime as dt
import gzip
import hashlib
import ipaddress
import json
import os
import re
import sqlite3
import time
import urllib.request
from pathlib import Path


LOG_RE = re.compile(
    r'^(?P<ip>\S+) \S+ \S+ \[(?P<time>[^\]]+)\] '
    r'"(?P<method>\S+) (?P<path>\S+) (?P<proto>[^"]+)" '
    r'(?P<status>\d+) (?P<size>\S+) "(?P<ref>[^"]*)" "(?P<ua>[^"]*)"'
)

LEGIT_PREFIXES = (
    "/ws",
    "/telemetry",
    "/api/ghosts",
    "/ghosts",
    "/dashboard/status",
    "/dashboard/health",
    "/events",
    "/status",
    "/health",
)
BOT_PREFIXES = (
    "/.env",
    "/.git",
    "/vendor",
    "/phpunit",
    "/cgi-bin",
    "/login",
    "/robots",
    "/wp-",
    "/wordpress",
    "/xmlrpc",
    "/index.php",
    "/phpinfo",
    "/actuator",
    "/server-status",
    "/dns-query",
    "/query",
    "/resolve",
    "/v1/",
    "/mcp",
    "/sse",
)
ASSET_PREFIXES = (
    "/assets/",
    "/game-assets/",
    "/favicon",
    "/manifest",
    "/pwa-",
    "/sw.js",
    "/workbox",
    "/website/",
)
INFRA_IP_PREFIXES = ("140.82.115.",)


def parse_time(raw: str) -> float:
    return dt.datetime.strptime(raw, "%d/%b/%Y:%H:%M:%S %z").timestamp()


def ip_hash(ip: str, salt: str) -> str:
    return hashlib.sha256((salt + ":" + ip).encode()).hexdigest()[:16]


def is_public_ip(ip: str) -> bool:
    try:
        return ipaddress.ip_address(ip).is_global
    except ValueError:
        return False


def classify(path: str, ua: str) -> str:
    lower = path.lower()
    if path.startswith(ASSET_PREFIXES):
        return "asset"
    if path.startswith(BOT_PREFIXES) or any(
        marker in lower for marker in ("eval-stdin", "passwd", "environ", ".env", "wp-content")
    ):
        return "scanner"
    if path.startswith("/webhook/deploy"):
        return "infra"
    if path.startswith(LEGIT_PREFIXES):
        return "candidate"
    if path in ("/", "/index.html") and ua and ua != "-":
        return "site_visit"
    return "other"


def iter_logs(log_dir: Path):
    for path in sorted(log_dir.glob("access.log*")):
        opener = gzip.open if str(path).endswith(".gz") else open
        with opener(path, "rt", errors="replace") as handle:
            for line in handle:
                match = LOG_RE.match(line)
                if match:
                    yield str(path), match.groupdict()


def geo_lookup(ips):
    result = {}
    fields = "status,message,country,countryCode,regionName,city,lat,lon,query"
    for index in range(0, len(ips), 100):
        batch = ips[index : index + 100]
        body = json.dumps([{"query": ip, "fields": fields} for ip in batch]).encode()
        req = urllib.request.Request(
            "http://ip-api.com/batch",
            data=body,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=20) as response:
            data = json.loads(response.read().decode())
        for row in data:
            if row.get("status") == "success":
                result[row["query"]] = row
        time.sleep(1.2)
    return result


def main() -> None:
    log_dir = Path(os.environ.get("ODISEA_NGINX_LOG_DIR", "/var/log/nginx"))
    out_db = Path(os.environ.get("ODISEA_GEO_DB", "/home/ubuntu/anna-central/data/geo_tags.db"))
    out_json = Path(os.environ.get("ODISEA_GEO_SUMMARY", "/home/ubuntu/anna-central/data/geo_nginx_summary.json"))
    salt = os.environ.get("ODISEA_GEO_HASH_SALT", "odisea-public-geo-v1")

    per_ip = {}
    total = 0
    files_seen = set()
    for log_path, rec in iter_logs(log_dir):
        files_seen.add(log_path)
        total += 1
        ip = rec["ip"]
        if not is_public_ip(ip):
            continue
        path = rec["path"]
        ts = parse_time(rec["time"])
        cls = classify(path, rec["ua"])
        row = per_ip.setdefault(
            ip,
            {
                "first_seen": ts,
                "last_seen": ts,
                "hits": 0,
                "candidate_hits": 0,
                "site_visit_hits": 0,
                "scanner_hits": 0,
                "asset_hits": 0,
                "infra_hits": 0,
                "other_hits": 0,
                "ws_hits": 0,
                "telemetry_hits": 0,
                "api_hits": 0,
                "paths": collections.Counter(),
            },
        )
        row["hits"] += 1
        row["first_seen"] = min(row["first_seen"], ts)
        row["last_seen"] = max(row["last_seen"], ts)
        row["paths"][path.split("?")[0]] += 1
        row[cls + "_hits"] += 1
        if path.startswith("/ws"):
            row["ws_hits"] += 1
        if path.startswith("/telemetry"):
            row["telemetry_hits"] += 1
        if path.startswith("/api/ghosts") or path.startswith("/ghosts"):
            row["api_hits"] += 1

    candidates = []
    for ip, row in per_ip.items():
        if ip.startswith(INFRA_IP_PREFIXES):
            continue
        signal = row["ws_hits"] + row["telemetry_hits"] + row["api_hits"] + row["site_visit_hits"]
        scanner_ratio = row["scanner_hits"] / max(1, row["hits"])
        if signal >= 2 and scanner_ratio < 0.5:
            candidates.append(ip)
    candidates.sort(
        key=lambda ip: -(
            per_ip[ip]["ws_hits"]
            + per_ip[ip]["telemetry_hits"]
            + per_ip[ip]["api_hits"]
            + per_ip[ip]["site_visit_hits"]
        )
    )

    geo = geo_lookup(candidates) if candidates else {}
    out_db.parent.mkdir(parents=True, exist_ok=True)
    backup = None
    if out_db.exists():
        backup = out_db.with_suffix(".db.bak_" + dt.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ"))
        backup.write_bytes(out_db.read_bytes())

    conn = sqlite3.connect(out_db)
    cur = conn.cursor()
    cur.execute(
        """CREATE TABLE IF NOT EXISTS geo_ips (
            ip_hash TEXT PRIMARY KEY,
            country TEXT,
            country_code TEXT,
            region TEXT,
            city TEXT,
            latitude REAL,
            longitude REAL,
            first_seen REAL,
            last_seen REAL,
            hits INTEGER,
            candidate_hits INTEGER,
            ws_hits INTEGER,
            telemetry_hits INTEGER,
            api_hits INTEGER,
            site_hits INTEGER,
            scanner_hits INTEGER,
            tagged_at REAL,
            source TEXT
        )"""
    )
    cur.execute(
        """CREATE TABLE IF NOT EXISTS geo_locations (
            country TEXT,
            country_code TEXT,
            region TEXT,
            city TEXT,
            latitude REAL,
            longitude REAL,
            player_count INTEGER,
            hit_count INTEGER,
            first_seen REAL,
            last_seen REAL,
            updated_at REAL,
            PRIMARY KEY(country_code, region, city, latitude, longitude)
        )"""
    )
    cur.execute("DELETE FROM geo_ips WHERE source = ?", ("nginx_access_log",))
    cur.execute("DELETE FROM geo_locations")

    now = time.time()
    locations = {}
    for ip in candidates:
        row = per_ip[ip]
        info = geo.get(ip)
        if not info:
            continue
        cur.execute(
            """INSERT OR REPLACE INTO geo_ips
               (ip_hash,country,country_code,region,city,latitude,longitude,
                first_seen,last_seen,hits,candidate_hits,ws_hits,telemetry_hits,
                api_hits,site_hits,scanner_hits,tagged_at,source)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                ip_hash(ip, salt),
                info.get("country"),
                info.get("countryCode"),
                info.get("regionName"),
                info.get("city"),
                info.get("lat"),
                info.get("lon"),
                row["first_seen"],
                row["last_seen"],
                row["hits"],
                row["candidate_hits"],
                row["ws_hits"],
                row["telemetry_hits"],
                row["api_hits"],
                row["site_visit_hits"],
                row["scanner_hits"],
                now,
                "nginx_access_log",
            ),
        )
        key = (
            info.get("country"),
            info.get("countryCode"),
            info.get("regionName"),
            info.get("city"),
            info.get("lat"),
            info.get("lon"),
        )
        agg = locations.setdefault(key, {"players": 0, "hits": 0, "first": row["first_seen"], "last": row["last_seen"]})
        agg["players"] += 1
        agg["hits"] += row["hits"]
        agg["first"] = min(agg["first"], row["first_seen"])
        agg["last"] = max(agg["last"], row["last_seen"])

    for key, agg in locations.items():
        cur.execute(
            """INSERT OR REPLACE INTO geo_locations
               (country,country_code,region,city,latitude,longitude,player_count,hit_count,first_seen,last_seen,updated_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
            (*key, agg["players"], agg["hits"], agg["first"], agg["last"], now),
        )
    conn.commit()
    conn.close()

    summary = {
        "generated_at": dt.datetime.utcnow().isoformat() + "Z",
        "logs": sorted(files_seen),
        "total_lines": total,
        "unique_public_ips": len(per_ip),
        "candidate_ips": len(candidates),
        "geolocated_ips": len(geo),
        "locations": [
            {
                "country": key[0],
                "country_code": key[1],
                "region": key[2],
                "city": key[3],
                "latitude": key[4],
                "longitude": key[5],
                **value,
            }
            for key, value in sorted(locations.items(), key=lambda item: -item[1]["hits"])
        ],
        "top_candidates": [
            {
                "ip_hash": ip_hash(ip, salt),
                "hits": per_ip[ip]["hits"],
                "ws_hits": per_ip[ip]["ws_hits"],
                "telemetry_hits": per_ip[ip]["telemetry_hits"],
                "api_hits": per_ip[ip]["api_hits"],
                "site_hits": per_ip[ip]["site_visit_hits"],
                "scanner_hits": per_ip[ip]["scanner_hits"],
                "geo": geo.get(ip),
                "top_paths": per_ip[ip]["paths"].most_common(8),
            }
            for ip in candidates[:25]
        ],
        "db": str(out_db),
        "backup": str(backup) if backup else None,
    }
    out_json.write_text(json.dumps(summary, indent=2, ensure_ascii=False))
    print(json.dumps(summary, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
