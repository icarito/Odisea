# Sistema de Actualización Segura (FD-228)

Guía operativa del mecanismo de updates de Odisea: cómo funciona, qué palancas
existen y qué responsabilidades implica operarlo. Para el detalle de implementación,
lea los archivos citados; este documento describe la **operación competente** del sistema.

---

## TL;DR — ¿basta con hacer push a `main`?

**Sí, con matices.** Hacer push a `main` dispara el build nocturno (canal `nightly`),
que firma manifiestos y los publica en el release `nightly` de GitHub. Los clientes
que ya tienen un build anterior **detectan** la actualización en el próximo arranque
y **ofrecen** instalarla.

Lo que NO ocurre automáticamente:

- **No se instala en silencio.** Salvo `severity: security_critical`, el usuario debe
  aceptar. El cliente solo descarga/aplica tras aceptación explícita.
- **No es instantáneo.** El cliente consulta al arrancar (y según su lógica de chequeo),
  no hay push hacia el dispositivo.
- **No sube de versión la rama `release`.** `main` → canal `nightly`. El canal estable
  `release` requiere push a la rama `release` (ver "Promover a estable").

---

## El flujo de extremo a extremo

```
push a main
   │
   ▼
CI: "Odyssey Pytest Runner" + "Asset Integrity"  (gate — deben pasar)
   │
   ▼
CI: "Release Multiplataforma" (export_all.yml, ~20 min)
   ├─ export por plataforma (linux x64/arm64, windows, macos, android, html5)
   ├─ job "manifests": firma manifest-<plat>-<arch>.json con UPDATE_SIGNING_KEY
   └─ job "nightly": recrea el release tag `nightly` con artifacts + manifiestos + .pub.pem
   │
   ▼
Central (odisea.educa.juegos): GET /game/updates/v1/manifest
   proxea el manifiesto firmado desde el release de GitHub (cache 5 min)
   │
   ▼
Cliente (UpdateManager autoload): al arrancar consulta el endpoint
   ├─ valida firma contra el keyring embebido (release-2026-a)
   ├─ aplica gates: secuencia, rollout %, min_supported_version
   ├─ emite update_available → UI (VersionNotification) propone
   ├─ usuario acepta → descarga por chunks → verifica SHA-256
   ├─ stagea como pending_boot → reinicia
   └─ arranque estable → Menu.gd llama confirm_boot() (commit)
```

Archivos clave:

- Generador/firmador: [scripts/update_manifest.py](../../../scripts/update_manifest.py)
- CI: [.github/workflows/export_all.yml](../../../.github/workflows/export_all.yml) (jobs `manifests`, `nightly`, `release`)
- Endpoint central: `odisea_central.py` → `handle_update_manifest` / `_get_manifest`
- Cliente: [UpdateManager.gd](UpdateManager.gd) (autoload, debe ser el primero)
- Verificador: [UpdateManifestVerifier.gd](UpdateManifestVerifier.gd)
- Keyring: [UpdateKeyring.gd](UpdateKeyring.gd) + claves en [keys/](keys/)
- UI: [../ui/VersionNotification.gd](../ui/VersionNotification.gd)

---

## Palancas (lo que usted controla por release)

Todas viven en el payload del manifiesto. Hoy el CI usa los **valores por defecto**
del generador; para cambiarlos se ajusta la invocación en `export_all.yml` o se pasa
el flag correspondiente a `update_manifest.py generate`.

| Palanca | Default | Efecto | Cómo cambiarla |
|---|---|---|---|
| `severity` | `optional` | `optional`: toast descartable. `recommended`: aviso persistente. `security_critical`: modal bloqueante + guarda checkpoint, no se puede descartar. | Editar `payload["severity"]` en [update_manifest.py](../../../scripts/update_manifest.py); idealmente exponer como flag `--severity`. |
| `rollout_percent` | `100` | Despliegue gradual. El cliente calcula un bucket determinista (hash de installation_id) y se excluye si `bucket >= rollout_percent*100`. Ej: `25` = ~25% de instalaciones. | `payload["rollout_percent"]`. Subir progresivamente: 10 → 50 → 100. |
| `min_supported_version` | `0.0.0` | Versión mínima soportada (gate de compatibilidad). | Flag `--min-supported-version`. |
| `force_full` | `false` | `true` deshabilita deltas; obliga descarga completa del artifact. | `payload["force_full"]`. Usar si un delta podría corromper. |
| `expires_at` | +30 días | Vencimiento del manifiesto. | `payload["expires_at"]`. |
| `channel` | derivado de la rama | `nightly` (main) / `release` (release). El central mapea canal → tag de release. | Rama de git, no se toca a mano. |

> **release_sequence** se deriva de `build_id` (run_id de CI). El cliente recuerda las
> secuencias ya aceptadas (`accepted_sequences`) y nunca ofrece una secuencia ≤ a la
> instalada — esto previene downgrades y re-ofrecimientos. Es automático.

### Cómo el cliente interpreta `severity`

- `optional` → toast; si el usuario lo descarta, se recuerda el `manifest_id` y no
  vuelve a molestar por ese manifiesto.
- `recommended` → aviso persistente (no se autodescarta).
- `security_critical` → `modal_dim` bloqueante; guarda checkpoint si está en gameplay;
  no es descartable. Úselo solo para parches de seguridad reales.

---

## Comportamiento por plataforma

| Plataforma | Qué hace el cliente |
|---|---|
| Linux / Windows / macOS | Descarga `.pck` por chunks, verifica SHA-256, stagea como pending_boot, reinicia y aplica. |
| Android | `kind=apk`: valida SHA-256 y abre el intent del sistema para instalar el APK. No carga PCK. |
| iOS | No descarga artifacts; muestra enlace a App Store / TestFlight. |
| HTML5 | Delega en la shell: navega a `?build_id=xxx` (cache-busting). Sin verificación cripto (se sirve por HTTPS del dominio oficial). |

---

## Seguridad de arranque y rollback automático

El cliente tiene un watchdog de arranque (`_check_pending_boot`):

1. Tras instalar, el update queda como `pending_boot` y se reinicia.
2. Cada arranque incrementa `attempts`. Si supera **2 intentos** sin confirmar,
   se hace **rollback** (descarta el pending, vuelve al paquete confirmado).
3. Un arranque exitoso llama `confirm_boot()` (desde [Menu.gd](../ui/Menu.gd)),
   que promueve el pending a confirmado y limpia paquetes viejos.

Esto significa: **un build que crashea al arrancar se revierte solo**. No requiere
intervención. Pero implica un commitment (abajo).

---

## Sus deberes y compromisos como operador

1. **No publicar builds que crasheen al arrancar.** El rollback protege al usuario,
   pero un build roto en `nightly` desperdicia el ciclo. El gate de Pytest/Asset
   Integrity ayuda, pero no garantiza arranque limpio.

2. **`confirm_boot()` debe ejecutarse en un arranque sano.** Hoy lo llama
   [Menu.gd:20](../ui/Menu.gd). Si se refactoriza el arranque y se rompe esa llamada,
   **todo update se revertiría a los 2 intentos** aunque funcione. Es un invariante crítico.

3. **`severity: security_critical` es un contrato con el usuario.** Bloquea el juego.
   No abusar: degradar la confianza hace que ignoren avisos reales.

4. **Rollout gradual para cambios riesgosos.** Si un release toca sistemas sensibles,
   empezar con `rollout_percent` bajo y subir tras observar telemetría (ver
   [skill odisea-telemetry] y el dashboard).

5. **Rotación de clave — VENCE 2027-06-30.** La clave `release-2026-a` tiene ventana
   `not_before`/`not_after` en [UpdateKeyring.gd](UpdateKeyring.gd). Pasada esa fecha,
   el cliente rechaza toda firma. **Antes** de esa fecha hay que emitir `release-2026-b`
   (ver "Rotación de clave"). Esto es un compromiso ineludible.

6. **Proteger la clave privada.** Vive en `~/odisea-update-keys/release-2026-a.private.pem`
   (chmod 600, fuera del repo) y en el secret `UPDATE_SIGNING_KEY` de GitHub Actions.
   Si se filtra, cualquiera puede firmar updates maliciosos → rotar de inmediato.

---

## Promover a estable (`release`)

El canal `nightly` es para validación. Para liberar a usuarios estables:

```bash
git checkout release && git merge --ff-only main && git push origin release
```

Esto dispara el mismo pipeline con `channel=release`; el job `release` (en vez de
`nightly`) crea un release versionado. **La rama `release` SÍ falla el build si falta
`UPDATE_SIGNING_KEY`** (a diferencia de `main`, que solo lo saltea). Mismo par de claves
firma ambos canales.

---

## Rotación de clave (antes de 2027-06-30)

1. Generar par nuevo (RSA, el CI usa `openssl rsa -pubout`):
   ```bash
   openssl genrsa -out release-2026-b.private.pem 4096
   openssl rsa -in release-2026-b.private.pem -pubout -out release-2026-b.pub.pem
   ```
2. Agregar `release-2026-b` al `KEYRING` en [UpdateKeyring.gd](UpdateKeyring.gd) con su
   ventana de validez, y copiar el `.pub` a [keys/](keys/). **Mantener `release-2026-a`
   durante la transición** para que builds firmados con la clave vieja sigan validando.
3. Actualizar `KEY_ID="release-2026-b"` en [export_all.yml](../../../.github/workflows/export_all.yml)
   y el secret `UPDATE_SIGNING_KEY` con la nueva privada.
4. Liberar un build con la nueva clave y verificar end-to-end antes de retirar la vieja.

---

## Verificación rápida (curl)

```bash
curl -s -H "Accept: application/vnd.odisea.update-manifest.v1+json" \
  "https://odisea.educa.juegos/game/updates/v1/manifest?channel=nightly&platform=linux&arch=x86_64&current_version=0.0.1&current_build_id=old"
```

Notas:
- Requiere el header `Accept: application/vnd.odisea.update-manifest.v1+json` (si no, `400 invalid_accept_header`).
- El **arch** en el nombre es `x86_64`, no `linux_x64` (los manifiestos son `manifest-linux-x86_64.json`).
- El **primer** request tras un build nuevo puede dar `504` (~10s) mientras el central
  baja el manifiesto de GitHub; reintente — luego responde en ~1s (cache 5 min).
- `200` con `payload_b64` = manifiesto firmado servido. `204` = sin update. `400` con
  versión más nueva que el release = ya está al día.

---

## Resumen de un vistazo

| Pregunta | Respuesta |
|---|---|
| ¿Push a main = clientes actualizan? | Sí, pero **ofrecen** (no instalan en silencio) en el próximo arranque, canal nightly. |
| ¿Cómo forzar instalación obligatoria? | `severity: security_critical` (bloquea). |
| ¿Cómo desplegar gradual? | `rollout_percent` (subir 10→50→100). |
| ¿Cómo ir a usuarios estables? | Push a la rama `release`. |
| ¿Qué pasa si un build crashea? | Rollback automático tras 2 intentos. |
| ¿Compromiso ineludible? | Rotar la clave antes de **2027-06-30** y proteger la privada. |
