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
   proximo nightly. Siempre queda publico el aprobado MAS NUEVO.
4. Apple revisa de a un build por tren: si otro sigue en revision, la solicitud
   devuelve 422 ANOTHER_BUILD_IN_REVIEW, y la API no tiene forma de retirar una
   solicitud. Para que la revision la tenga siempre el build mas nuevo, el build
   viejo que sigue WAITING_FOR_REVIEW se EXPIRA (nunca fue publico) y se pide la
   revision del nuevo -- salvo que esa solicitud tenga menos de REVIEW_REFRESH_S
   o Apple ya lo este revisando (IN_REVIEW): ahi se respeta la cola.

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
from datetime import datetime, timezone

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
# Una solicitud de revision mas nueva que esto no se reemplaza por un build aun
# mas nuevo: cada reemplazo manda al build al fondo de la cola de Apple.
REVIEW_REFRESH_S = 2 * 3600


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


def newer_than_current(candidates: list[dict], current: list[dict]) -> list[dict]:
    """Candidatos subidos despues del build vigente mas reciente, del mas nuevo al mas viejo.

    Promover algo mas viejo que lo vigente seria ir para atras.
    """
    def fecha(b: dict) -> str:
        return b.get("attributes", {}).get("uploadedDate") or ""

    tope = max((fecha(b) for b in current), default="")
    ids = {b["id"] for b in current}
    return sorted((b for b in candidates if b["id"] not in ids and fecha(b) > tope),
                  key=fecha, reverse=True)


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


def review_submissions(page: dict) -> dict[str, dict | None]:
    """{build_id: atributos de su betaAppReviewSubmission, o None si nunca se pidio}.

    `page` es un listado de builds pedido con include=betaAppReviewSubmission.
    """
    subs = {i["id"]: i.get("attributes", {}) for i in page.get("included", [])
            if i.get("type") == "betaAppReviewSubmissions"}
    out = {}
    for b in page.get("data", []):
        rel = ((b.get("relationships") or {}).get("betaAppReviewSubmission") or {}).get("data")
        out[b["id"]] = subs.get(rel["id"]) if rel else None
    return out


def review_state(subs: dict[str, dict | None], build_id: str) -> str | None:
    return (subs.get(build_id) or {}).get("betaReviewState")


def parse_date(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value.replace("Z", "+00:00")) if value else None


def review_plan(builds: list[dict], subs: dict[str, dict | None],
                now: datetime) -> tuple[str | None, list[str]]:
    """(build a enviar a revision o None, builds pendientes a expirar antes).

    `builds` va del mas nuevo al mas viejo. La revision le toca al mas nuevo,
    salvo que ya la tenga (en cualquier estado), que Apple este revisando otro
    (IN_REVIEW) o que la ultima solicitud pendiente tenga menos de REVIEW_REFRESH_S.
    """
    if not builds or subs.get(builds[0]["id"]) is not None:
        return None, []
    pendientes = [b for b in builds[1:]
                  if review_state(subs, b["id"]) in ("WAITING_FOR_REVIEW", "IN_REVIEW")]
    if any(review_state(subs, b["id"]) == "IN_REVIEW" for b in pendientes):
        return None, []
    ultima = max(
        (parse_date((subs[b["id"]] or {}).get("submittedDate")
                    or b["attributes"].get("uploadedDate")) for b in pendientes),
        default=None,
    )
    if ultima and (now - ultima).total_seconds() < REVIEW_REFRESH_S:
        return None, []
    return builds[0]["id"], [b["id"] for b in pendientes]


def expire_build(build_id: str) -> None:
    """Expira el build: es la unica forma por API de sacarlo de la cola de revision."""
    call("PATCH", f"/v1/builds/{build_id}",
         {"data": {"type": "builds", "id": build_id, "attributes": {"expired": True}}})


def submit_beta_review(build_id: str) -> bool:
    """Pide a Apple la revision de este build. True si quedo pedida.

    Idempotente: un 409 (ya pedida) cuenta como pedida. Apple revisa de a un build
    por tren (misma version y plataforma): si otro sigue en revision responde 422
    ANOTHER_BUILD_IN_REVIEW. Eso no es un error, es la cola de Apple -- devuelve
    False y `--promote` lo vuelve a pedir cuando el otro termine.
    """
    try:
        call(
            "POST",
            "/v1/betaAppReviewSubmissions",
            {"data": {"type": "betaAppReviewSubmissions",
                      "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}},
        )
    except SystemExit as exc:
        if "ANOTHER_BUILD_IN_REVIEW" in str(exc):
            return False
        if "-> 409" not in str(exc):
            raise
    return True


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


def app_and_groups(bundle_id: str) -> tuple[str, list[dict], list[str]]:
    apps = call("GET", f"/v1/apps?filter[bundleId]={bundle_id}&limit=1")["data"]
    if not apps:
        raise SystemExit(f"No app in App Store Connect for bundle id {bundle_id}")
    app_id = apps[0]["id"]
    groups = call("GET", f"/v1/betaGroups?filter[app]={app_id}&limit=200")["data"]
    targets = external_group_ids(groups)
    if not targets:
        raise SystemExit("No external beta groups configured for this app")
    return app_id, groups, targets


def sync_platform(app_id: str, groups: list[dict], targets: list[str], platform: str) -> None:
    """Deja la revision en el build mas nuevo y publica el aprobado mas nuevo."""
    # ponytail: ventana de 50 builds; un pendiente mas viejo que eso no se expira
    # y la solicitud nueva vuelve con 422 (queda logueado).
    page = call(
        "GET",
        f"/v1/builds?filter[app]={app_id}&filter[preReleaseVersion.platform]={platform}"
        "&filter[processingState]=VALID&filter[expired]=false&sort=-uploadedDate&limit=50"
        "&include=betaAppReviewSubmission",
    )
    builds = page["data"]
    if not builds:
        return
    subs = review_submissions(page)
    numero = {b["id"]: b["attributes"].get("version", b["id"]) for b in builds}
    newest = builds[0]

    submit_id, expirar = review_plan(builds, subs, datetime.now(timezone.utc))
    if submit_id:
        for bid in expirar:
            expire_build(bid)
            print(f"build {numero[bid]} ({platform}): expirado para cederle la revisión "
                  f"a {numero[submit_id]}")
        if needs_compliance_answer(newest):
            declare_no_encryption(newest["id"])
        if submit_beta_review(submit_id):
            subs[submit_id] = {"betaReviewState": "WAITING_FOR_REVIEW"}
            print(f"build {numero[submit_id]} ({platform}): enviado a Beta App Review")
        else:
            print(f"build {numero[submit_id]} ({platform}): Apple sigue con otro build del "
                  "tren en revisión; se reintenta en la próxima corrida")
    elif subs.get(newest["id"]) is None:
        print(f"build {numero[newest['id']]} ({platform}): hay otra revisión en curso o "
              "pedida hace menos de 2 h; se respeta la cola")

    aprobado = next((b for b in builds if review_state(subs, b["id"]) == "APPROVED"), None)
    if not aprobado:
        return
    vigentes = [
        b
        for gid in targets
        for b in call_all(
            f"/v1/builds?filter[betaGroups]={gid}"
            f"&filter[preReleaseVersion.platform]={platform}&limit=200"
        )
    ]
    if newer_than_current([aprobado], vigentes):
        print(f"build {numero[aprobado['id']]} ({platform}): aprobado por Apple, "
              "promoviendo al grupo externo")
        assign_to_external_groups(groups, targets, platform, numero[aprobado["id"]],
                                  aprobado["id"])


def main() -> int:
    build_number = os.environ["BUILD_NUMBER"]
    platforms = platforms_from_env(os.environ.get("PLATFORMS", ""))
    app_id, groups, targets = app_and_groups(os.environ["BUNDLE_ID"])

    # El build aparece casi enseguida pero queda en PROCESSING; no se puede asignar
    # a un grupo hasta que pase a VALID.
    found = wait_for_builds(app_id, build_number, platforms)
    for platform, build in found.items():
        if needs_compliance_answer(build):
            declare_no_encryption(build["id"])
            print(f"build {build_number} ({platform}): cumplimiento de exportación "
                  "respondido (sin criptografía no exenta)")
        sync_platform(app_id, groups, targets, platform)
    return 0


def promote() -> int:
    """Cron independiente del export: la revision de Apple tarda mas que ese job."""
    platforms = platforms_from_env(os.environ.get("PLATFORMS", ""))
    app_id, groups, targets = app_and_groups(os.environ["BUNDLE_ID"])
    for platform in platforms:
        sync_platform(app_id, groups, targets, platform)
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

    ids = lambda bs: [x["id"] for x in bs]  # noqa: E731
    # vigente v1; v2 y v3 son posteriores, del mas nuevo al mas viejo
    assert ids(newer_than_current(builds, [b("v1", "2026-01-01")])) == ["v3", "v2"]
    assert ids(newer_than_current(builds, [b("v3", "2026-03-01")])) == []   # nada mas nuevo
    assert ids(newer_than_current(builds, [])) == ["v3", "v2", "v1"]        # grupo vacio
    # grupos con vigentes distintos: manda el mas reciente
    assert ids(newer_than_current(builds, [b("v1", "2026-01-01"), b("v2", "2026-02-01")])) == ["v3"]

    # review_plan: la revision le toca al mas nuevo salvo cola reciente o IN_REVIEW
    now = datetime(2026, 9, 14, 12, tzinfo=timezone.utc)
    nb = [b("n3", "2026-09-14T10:00:00Z"), b("n2", "2026-09-13T10:00:00Z"),
          b("n1", "2026-09-12T10:00:00Z")]

    def sub(state, fecha=None):
        return {"betaReviewState": state, "submittedDate": fecha}

    assert review_plan(nb, {}, now) == ("n3", [])                         # cola libre
    assert review_plan(nb, {"n2": sub("WAITING_FOR_REVIEW", "2026-09-14T08:00:00Z")},
                       now) == ("n3", ["n2"])                             # pendiente viejo: se reemplaza
    assert review_plan(nb, {"n2": sub("WAITING_FOR_REVIEW", "2026-09-14T11:00:00Z")},
                       now) == (None, [])                                 # pedida hace 1 h: se espera
    assert review_plan(nb, {"n2": sub("IN_REVIEW", "2026-09-13T11:00:00Z")},
                       now) == (None, [])                                 # Apple revisando: no se corta
    assert review_plan(nb, {"n3": sub("WAITING_FOR_REVIEW")}, now) == (None, [])   # ya la tiene
    assert review_plan(nb, {"n2": sub("APPROVED"), "n1": sub("REJECTED")}, now) == ("n3", [])
    assert review_plan([], {}, now) == (None, [])

    page = {"data": [{"id": "x", "relationships": {"betaAppReviewSubmission": {"data": {"id": "s"}}}},
                     {"id": "y", "relationships": {"betaAppReviewSubmission": {"data": None}}}],
            "included": [{"type": "betaAppReviewSubmissions", "id": "s",
                          "attributes": {"betaReviewState": "APPROVED"}}]}
    assert review_submissions(page) == {"x": {"betaReviewState": "APPROVED"}, "y": None}

    # submit_beta_review: 422 de cola -> False, 409 -> True, otro error -> falla
    global call
    real_call = call
    try:
        for msg, esperado in (("-> 422: ANOTHER_BUILD_IN_REVIEW", False), ("-> 409: dup", True)):
            def call(*_a, _m=msg, **_k):  # noqa: F811
                raise SystemExit(f"ASC POST x {_m}")
            assert submit_beta_review("b") is esperado, msg

        def call(*_a, **_k):  # noqa: F811
            raise SystemExit("ASC POST x -> 422: ENTITY_ERROR")
        try:
            submit_beta_review("b")
            raise AssertionError("un 422 que no es de cola debe fallar")
        except SystemExit:
            pass
    finally:
        call = real_call
    print("self-test OK")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        raise SystemExit(self_test())
    raise SystemExit(promote() if "--promote" in sys.argv else main())
