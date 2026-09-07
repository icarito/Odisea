#!/usr/bin/env python3
"""Asigna un build recién subido a TestFlight a los grupos EXTERNOS de la app.

altool sube el IPA pero no lo distribuye: el build queda solo para testers
internos hasta que alguien lo mueve a mano al grupo externo. Este script hace ese
paso con la App Store Connect API: espera a que Apple termine de procesar el
build y lo agrega a todos los grupos externos.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_API_KEY_P8, BUNDLE_ID, BUILD_NUMBER.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com"
POLL_TIMEOUT_S = 45 * 60
POLL_INTERVAL_S = 60
# Si el build ni siquiera aparece en este plazo, es que no se subió (la pata iOS se
# saltó por falta de secrets): salir limpio en vez de agotar los 45 minutos.
NOT_FOUND_GRACE_S = 10 * 60


def token() -> str:
    import jwt  # importado acá para que --self-test corra sin PyJWT instalado

    return jwt.encode(
        {
            "iss": os.environ["ASC_ISSUER_ID"],
            "iat": int(time.time()),
            "exp": int(time.time()) + 20 * 60,
            "aud": "appstoreconnect-v1",
        },
        os.environ["ASC_API_KEY_P8"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method: str, path: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(
        f"{API}{path}",
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raise SystemExit(f"ASC {method} {path} -> {exc.code}: {exc.read().decode()}") from exc


def external_group_ids(groups: list[dict]) -> list[str]:
    return [g["id"] for g in groups if not g["attributes"].get("isInternalGroup")]


def main() -> int:
    bundle_id = os.environ["BUNDLE_ID"]
    build_number = os.environ["BUILD_NUMBER"]

    apps = call("GET", f"/v1/apps?filter[bundleId]={bundle_id}&limit=1")["data"]
    if not apps:
        raise SystemExit(f"No app in App Store Connect for bundle id {bundle_id}")
    app_id = apps[0]["id"]

    # El build aparece casi enseguida pero queda en PROCESSING; no se puede asignar
    # a un grupo hasta que pase a VALID.
    started = time.time()
    deadline = started + POLL_TIMEOUT_S
    build_id = None
    while True:
        builds = call(
            "GET",
            f"/v1/builds?filter[app]={app_id}&filter[version]={build_number}&limit=1",
        )["data"]
        state = builds[0]["attributes"]["processingState"] if builds else "NOT_FOUND"
        print(f"build {build_number}: {state}", flush=True)
        if state == "VALID":
            build_id = builds[0]["id"]
            break
        if state in ("INVALID", "FAILED"):
            raise SystemExit(f"Apple rejected build {build_number}: {state}")
        if state == "NOT_FOUND" and time.time() - started >= NOT_FOUND_GRACE_S:
            print(f"Build {build_number} nunca llegó a App Store Connect — nada que distribuir.")
            return 0
        if time.time() >= deadline:
            raise SystemExit(f"Timed out waiting for build {build_number} (last state: {state})")
        time.sleep(POLL_INTERVAL_S)

    groups = call("GET", f"/v1/betaGroups?filter[app]={app_id}&limit=200")["data"]
    targets = external_group_ids(groups)
    if not targets:
        raise SystemExit("No external beta groups configured for this app")

    for gid in targets:
        name = next(g["attributes"]["name"] for g in groups if g["id"] == gid)
        call(
            "POST",
            f"/v1/betaGroups/{gid}/relationships/builds",
            {"data": [{"type": "builds", "id": build_id}]},
        )
        print(f"build {build_number} -> grupo externo '{name}'")
    return 0


def self_test() -> int:
    groups = [
        {"id": "int", "attributes": {"name": "Equipo", "isInternalGroup": True}},
        {"id": "ext", "attributes": {"name": "Externos", "isInternalGroup": False}},
        {"id": "old", "attributes": {"name": "Legacy"}},
    ]
    assert external_group_ids(groups) == ["ext", "old"], external_group_ids(groups)
    assert external_group_ids([]) == []
    print("self-test OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(self_test() if "--self-test" in sys.argv else main())
