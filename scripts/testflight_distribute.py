#!/usr/bin/env python3
"""Asigna un build recién subido a TestFlight a los grupos EXTERNOS de la app.

altool sube el IPA (o el .pkg de macOS) pero no lo distribuye: el build queda
solo para testers internos hasta que alguien lo mueve a mano al grupo externo.
Este script hace ese paso con la App Store Connect API: espera a que Apple
termine de procesar el build, responde el cuestionario de exportacion y lo
agrega a todos los grupos externos.

iOS y macOS son la misma app (compra universal): comparten bundle id y numero de
build, y se distinguen unicamente por la plataforma del preReleaseVersion. Por
eso cada consulta filtra por plataforma; sin ese filtro una sola de las dos se
lleva la distribucion y la otra se queda sin publicar.

Agregar es aditivo: la API no des-promueve nada sola. Apple deja compartir hasta
100 builds y cada uno caduca a los 90 dias, asi que un nightly diario no llega al
tope -- pero cualquier dia con dos builds si, dentro de esa ventana. Por eso el
script deja en cada grupo externo solo los KEEP_IN_GROUP mas recientes y saca el
resto DEL GRUPO (no los expira: siguen visibles para testers internos y caducan
solos). La poda tambien es por plataforma: si no, cada build de macOS desalojaria
uno de iOS y la retencion real seria la mitad.

Todo build nuevo en un grupo externo requiere Beta App Review de Apple antes de
que los testers puedan instalarlo. Agregarlo al grupo ANTES de esa aprobacion no
lo hace instalable pero SI le saca su lugar al build anterior (ya aprobado) en la
poda por KEEP_IN_GROUP, dejando a los testers externos sin build utilizable hasta
que Apple revise el nuevo -- que puede tardar horas o dias. Por eso este script:

1. Pide la revision (POST a betaAppReviewSubmissions) apenas el build esta VALID,
   en vez de esperar a que alguien la pida a mano en la web.
2. NO agrega el build a los grupos externos hasta que su revision este APPROVED.
   Mientras tanto el build previo (ya aprobado) sigue siendo el vigente: nunca se
   lo saca del grupo por un build que todavia no se puede instalar.
3. Un modo `--promote` separado (pensado para un cron periodico, no atado al
   pipeline de export) vuelve a chequear builds que quedaron pendientes de
   revision y los promueve al grupo apenas Apple los aprueba, sin esperar al
   proximo nightly.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_API_KEY_P8, BUNDLE_ID, BUILD_NUMBER,
PLATFORMS (lista separada por comas, por defecto IOS).

`--promote` no usa BUILD_NUMBER: recorre los builds recientes de cada plataforma
buscando el mas nuevo que ya este APPROVED y todavia no este en los grupos
externos.
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
# Cuantos builds quedan disponibles en cada grupo externo, POR PLATAFORMA. Los
# testers instalan el ultimo; los anteriores son para poder volver atras si el
# nuevo sale mal.
KEEP_IN_GROUP = 5


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
        path if path.startswith("http") else f"{API}{path}",
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


def call_all(path: str) -> list[dict]:
    """Sigue links.next hasta agotar la coleccion."""
    out: list[dict] = []
    while path:
        page = call("GET", path)
        out.extend(page.get("data", []))
        path = page.get("links", {}).get("next", "")
    return out


def external_group_ids(groups: list[dict]) -> list[str]:
    return [g["id"] for g in groups if not g["attributes"].get("isInternalGroup")]


def platforms_from_env(value: str) -> list[str]:
    """IOS,MAC_OS -> ["IOS", "MAC_OS"]. Vacio o ausente = solo iOS."""
    return [p.strip().upper() for p in (value or "IOS").split(",") if p.strip()]


def needs_compliance_answer(build: dict) -> bool:
    """True si el build todavia no tiene respondido el cuestionario de exportacion.

    Apple deja el campo en null hasta que alguien contesta (a mano en la web, con
    ITSAppUsesNonExemptEncryption en el Info.plist, o por API). Mientras siga en
    null el build aparece como "Missing Compliance" y TestFlight NO lo entrega a
    testers externos, aunque este VALID y asignado al grupo.
    """
    return build.get("attributes", {}).get("usesNonExemptEncryption") is None


def stale_build_ids(builds: list[dict], keep: int, protected: str) -> list[str]:
    """Los ids a sacar del grupo: todo lo viejo salvo los `keep` mas recientes.

    `protected` es el build que acabamos de promover; nunca se saca, aunque la
    fecha de subida venga vacia y quede al fondo del orden.
    """
    ordenados = sorted(
        builds,
        key=lambda b: b.get("attributes", {}).get("uploadedDate") or "",
        reverse=True,
    )
    return [b["id"] for b in ordenados[keep:] if b["id"] != protected]


def wait_for_builds(app_id: str, build_number: str, platforms: list[str]) -> dict[str, dict]:
    """Espera a que Apple procese el build de cada plataforma. Devuelve {plataforma: build}.

    Las plataformas se esperan a la vez, no una detras de otra: comparten numero
    de build y Apple las procesa en paralelo, asi que encadenar las esperas solo
    lograria que un timeout de iOS dejara a macOS sin distribuir.

    Una plataforma que no aparece en NOT_FOUND_GRACE_S se da por no subida (su
    pata del workflow se salteo por falta de secrets) y se descarta sin fallar.
    """
    started = time.time()
    deadline = started + POLL_TIMEOUT_S
    found: dict[str, dict] = {}
    pending = list(platforms)
    while pending:
        for platform in list(pending):
            builds = call(
                "GET",
                f"/v1/builds?filter[app]={app_id}&filter[version]={build_number}"
                f"&filter[preReleaseVersion.platform]={platform}&limit=1",
            )["data"]
            state = builds[0]["attributes"]["processingState"] if builds else "NOT_FOUND"
            print(f"build {build_number} ({platform}): {state}", flush=True)
            if state == "VALID":
                found[platform] = builds[0]
                pending.remove(platform)
            elif state in ("INVALID", "FAILED"):
                raise SystemExit(f"Apple rejected build {build_number} ({platform}): {state}")
            elif state == "NOT_FOUND" and time.time() - started >= NOT_FOUND_GRACE_S:
                print(f"Build {build_number} ({platform}) nunca llegó a App Store Connect "
                      "— nada que distribuir para esa plataforma.")
                pending.remove(platform)
        if not pending:
            break
        if time.time() >= deadline:
            raise SystemExit(
                f"Timed out waiting for build {build_number}: {', '.join(pending)}")
        time.sleep(POLL_INTERVAL_S)
    return found


def fetch_beta_review_state(build_id: str) -> str | None:
    """Estado de la revision de Apple para este build, o None si nunca se pidio.

    `WAITING_FOR_REVIEW` | `IN_REVIEW` | `REJECTED` | `APPROVED`. Un build sin
    Beta App Review Submission todavia no fue enviado a revisar (ni a mano en la
    web ni por API) y no aparece en `included`.
    """
    data = call("GET", f"/v1/builds/{build_id}?include=betaAppReviewSubmission")
    for item in data.get("included", []):
        if item.get("type") == "betaAppReviewSubmissions":
            return item.get("attributes", {}).get("betaReviewState")
    return None


def submit_beta_review(build_id: str) -> None:
    """Pide a Apple la revision de este build. Idempotente: ignora un 409 (ya pedida)."""
    try:
        call(
            "POST",
            "/v1/betaAppReviewSubmissions",
            {"data": {"type": "betaAppReviewSubmissions",
                      "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}},
        )
    except SystemExit as exc:
        if "-> 409" not in str(exc):
            raise


def declare_no_encryption(build_id: str) -> None:
    """Contesta por API que el build no usa criptografia no exenta.

    El juego solo habla HTTPS con el central (telemetria y updates); HTTPS del
    sistema es exento, asi que la respuesta es "no". Hacerlo por API en vez de
    con ITSAppUsesNonExemptEncryption en el Info.plist sirve para las dos
    plataformas desde un solo lugar: el .app de macOS se firma en el workflow y
    tocar su plist despues de firmar invalidaria la firma.
    """
    call(
        "PATCH",
        f"/v1/builds/{build_id}",
        {"data": {"type": "builds", "id": build_id,
                  "attributes": {"usesNonExemptEncryption": False}}},
    )


def assign_to_external_groups(groups: list[dict], targets: list[str], platform: str,
                               build_number: str, build_id: str) -> None:
    """Agrega `build_id` a los grupos externos y poda los viejos de esa plataforma.

    Solo se debe llamar con un build ya APPROVED por Apple: es el unico momento en
    que reemplazar al build vigente no deja a los testers externos sin nada
    instalable.
    """
    for gid in targets:
        name = next(g["attributes"]["name"] for g in groups if g["id"] == gid)
        call(
            "POST",
            f"/v1/betaGroups/{gid}/relationships/builds",
            {"data": [{"type": "builds", "id": build_id}]},
        )
        print(f"build {build_number} ({platform}) -> grupo externo '{name}'")

        # Solo los builds de ESTA plataforma compiten por los KEEP_IN_GROUP
        # lugares: /v1/betaGroups/{id}/builds los devuelve todos mezclados.
        en_grupo = call_all(
            f"/v1/builds?filter[betaGroups]={gid}"
            f"&filter[preReleaseVersion.platform]={platform}&limit=200"
        )
        sobran = stale_build_ids(en_grupo, KEEP_IN_GROUP, build_id)
        if sobran:
            call(
                "DELETE",
                f"/v1/betaGroups/{gid}/relationships/builds",
                {"data": [{"type": "builds", "id": b} for b in sobran]},
            )
        print(f"  '{name}' ({platform}): {len(sobran)} build(s) viejo(s) fuera del "
              f"grupo, quedan los {KEEP_IN_GROUP} mas recientes")


def main() -> int:
    bundle_id = os.environ["BUNDLE_ID"]
    build_number = os.environ["BUILD_NUMBER"]
    platforms = platforms_from_env(os.environ.get("PLATFORMS", ""))

    apps = call("GET", f"/v1/apps?filter[bundleId]={bundle_id}&limit=1")["data"]
    if not apps:
        raise SystemExit(f"No app in App Store Connect for bundle id {bundle_id}")
    app_id = apps[0]["id"]

    # El build aparece casi enseguida pero queda en PROCESSING; no se puede asignar
    # a un grupo hasta que pase a VALID.
    found = wait_for_builds(app_id, build_number, platforms)
    if not found:
        return 0

    groups = call("GET", f"/v1/betaGroups?filter[app]={app_id}&limit=200")["data"]
    targets = external_group_ids(groups)
    if not targets:
        raise SystemExit("No external beta groups configured for this app")

    for platform, build in found.items():
        build_id = build["id"]
        if needs_compliance_answer(build):
            declare_no_encryption(build_id)
            print(f"build {build_number} ({platform}): cumplimiento de exportación "
                  "respondido (sin criptografía no exenta)")

        review_state = fetch_beta_review_state(build_id)
        if review_state is None:
            submit_beta_review(build_id)
            review_state = "WAITING_FOR_REVIEW"
            print(f"build {build_number} ({platform}): enviado a Beta App Review")

        if review_state != "APPROVED":
            print(f"build {build_number} ({platform}): revisión de Apple en estado "
                  f"{review_state}; se deja el build externo anterior activo hasta "
                  "que este se apruebe (ver `--promote`).")
            continue

        assign_to_external_groups(groups, targets, platform, build_number, build_id)
    return 0


def promote() -> int:
    """Promueve al grupo externo el build mas nuevo ya APPROVED que quedo pendiente.

    Pensado para correr en un cron independiente del pipeline de export: la
    revision de Apple puede tardar mas que la ventana de ese job, asi que esto
    la retoma sin esperar al proximo nightly.
    """
    bundle_id = os.environ["BUNDLE_ID"]
    platforms = platforms_from_env(os.environ.get("PLATFORMS", ""))

    apps = call("GET", f"/v1/apps?filter[bundleId]={bundle_id}&limit=1")["data"]
    if not apps:
        raise SystemExit(f"No app in App Store Connect for bundle id {bundle_id}")
    app_id = apps[0]["id"]

    groups = call("GET", f"/v1/betaGroups?filter[app]={app_id}&limit=200")["data"]
    targets = external_group_ids(groups)
    if not targets:
        raise SystemExit("No external beta groups configured for this app")

    for platform in platforms:
        candidatos = call(
            "GET",
            f"/v1/builds?filter[app]={app_id}&filter[preReleaseVersion.platform]={platform}"
            "&filter[processingState]=VALID&sort=-uploadedDate&limit=10",
        )["data"]
        if not candidatos:
            continue

        vigentes = {
            b["id"]
            for gid in targets
            for b in call_all(
                f"/v1/builds?filter[betaGroups]={gid}"
                f"&filter[preReleaseVersion.platform]={platform}&limit=200"
            )
        }

        # Solo el mas nuevo importa: si todavia no esta aprobado, uno mas viejo
        # tampoco deberia reemplazar al build vigente (seria ir para atras).
        newest = candidatos[0]
        build_id = newest["id"]
        build_number = newest["attributes"].get("version", build_id)
        if build_id in vigentes:
            continue  # ya es el vigente, nada que promover
        if fetch_beta_review_state(build_id) == "APPROVED":
            print(f"build {build_number} ({platform}): aprobado por Apple, "
                  "promoviendo al grupo externo")
            assign_to_external_groups(groups, targets, platform, build_number, build_id)
    return 0


def self_test() -> int:
    groups = [
        {"id": "int", "attributes": {"name": "Equipo", "isInternalGroup": True}},
        {"id": "ext", "attributes": {"name": "Externos", "isInternalGroup": False}},
        {"id": "old", "attributes": {"name": "Legacy"}},
    ]
    assert external_group_ids(groups) == ["ext", "old"], external_group_ids(groups)
    assert external_group_ids([]) == []

    assert platforms_from_env("IOS,MAC_OS") == ["IOS", "MAC_OS"]
    assert platforms_from_env(" ios , mac_os ") == ["IOS", "MAC_OS"]
    assert platforms_from_env("") == ["IOS"]                    # default: solo iOS

    # null = sin responder (Missing Compliance); False/True = ya respondido.
    assert needs_compliance_answer({"attributes": {"usesNonExemptEncryption": None}})
    assert needs_compliance_answer({"attributes": {}})
    assert not needs_compliance_answer({"attributes": {"usesNonExemptEncryption": False}})
    assert not needs_compliance_answer({"attributes": {"usesNonExemptEncryption": True}})

    def b(i, fecha):
        return {"id": i, "attributes": {"uploadedDate": fecha}}

    builds = [b("v1", "2026-01-01"), b("v3", "2026-03-01"), b("v2", "2026-02-01")]
    assert stale_build_ids(builds, 2, "v3") == ["v1"]
    assert stale_build_ids(builds, 5, "v3") == []          # menos que el tope: nada que sacar
    assert stale_build_ids(builds, 1, "v1") == ["v2"]      # el protegido no sale aunque sea viejo
    assert stale_build_ids([b("x", None)], 0, "otro") == ["x"]   # sin fecha, igual se ordena
    print("self-test OK")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        raise SystemExit(self_test())
    raise SystemExit(promote() if "--promote" in sys.argv else main())
