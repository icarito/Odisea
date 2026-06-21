# FD-228 / Etapa 4+5 — Cliente: Descarga, Selección, Aplicación y Rollback

## Contexto
FD-228 define un sistema de actualización segura. Esta etapa implementa el cliente del update system: el autoload UpdateManager con descarga por chunks con resume, selección delta/full, aplicación al boot, y rollback automático.

## Archivos a modificar/crear
- `core_v2/update/UpdateManager.gd` (new autoload)
- `core_v2/update/UpdateKeyring.gd` (new — keyring de solo lectura)
- `core_v2/update/UpdateManifestVerifier.gd` (new — verificación criptográfica)
- `core_v2/update/keys/release-2026-a.pub` (new — clave pública para tests/staging)
- `core_v2/systems/VersionChecker.gd` (modify — compatibilidad)
- `project.godot` (modify — autoload order)
- `core_v2/tests/test_update_manifest_v2.gd` (new)

## Requerimientos

### UpdateKeyring (UpdateKeyring.gd)
Keyring de solo lectura embebido en el cliente, con ventanas de validez:
```json
{
  "release-2026-a": {
    "algorithm": "RSASSA-PKCS1-v1_5-SHA256",
    "public_key_path": "res://core_v2/update/keys/release-2026-a.pub",
    "not_before": "2026-06-21T00:00:00Z",
    "not_after": "2027-06-30T23:59:59Z"
  }
}
```
API: `get_key(key_id: String) -> Dictionary`, `get_valid_keys(at_time: int) -> Array`.

### UpdateManifestVerifier (UpdateManifestVerifier.gd)
Verifica el sobre firmado:

1. Decodificar `payload_b64` del sobre
2. Para cada firma en `signatures`, buscar la clave correspondiente en el keyring
3. Si la clave existe y está en ventana de validez: verificar firma con `Crypto.verify()`
4. Algoritmo: RSASSA-PKCS1-v1_5-SHA256 (Godot 3.6 Crypto.verify con HashingContext.HASH_SHA256)
5. Si ninguna firma es válida → rechazar todo el sobre
6. Si payload_b64 no decodifica, JSON inválido, o campos faltantes → rechazar
7. Si schema_version no es conocido → rechazar
8. No canonicalizar ni reserializar el JSON antes de verificar
9. Límite: 2 MiB máximo para el sobre

API: `verify(envelope: Dictionary) -> Dictionary` (devuelve payload decodificado o null + error_code)

### UpdateManager (UpdateManager.gd — primer autoload)

**Estados:**
```text
idle → checking → available → downloading → verifying → ready_to_restart
                                                                    → applying_external
                                                                    → blocked_critical
failed
```

**API pública:**
```gdscript
signal update_available(info)
signal update_progress(downloaded_bytes, total_bytes)
signal update_ready(info)
signal update_failed(code, recoverable)

func check_for_updates() -> void
func get_current_update() -> Dictionary
func begin_update() -> void
func cancel_download() -> void
func request_restart() -> void
func confirm_boot() -> void
func get_status() -> String
```

**Códigos de error estables:**
network_unavailable, invalid_response, unknown_schema, unknown_key, invalid_signature, manifest_expired, channel_mismatch, platform_mismatch, replay_rejected, not_in_rollout, insufficient_storage, download_failed, chunk_hash_mismatch, artifact_hash_mismatch, state_corrupt, load_pack_failed, external_install_failed

**Flujo de check:**
1. HTTP GET a `/game/updates/v1/manifest?channel=...&platform=...&arch=...&current_version=...&current_build_id=...`
2. Si 204 → no hay update
3. Si 200 → obtener sobre firmado
4. Verificar con UpdateManifestVerifier
5. Obtener payload verificado
6. Validar: channel coincide, platform coincide, release_sequence > último aceptado, no expirado, rollout_bucket dentro del rollout
7. Emitir update_available(signal)

**Cálculo de rollout (local, no confiar en servidor):**
```gdscript
var digest = SHA256(UTF8(installation_id + ":" + manifest_id))
var bucket = (digest[0] << 24 | digest[1] << 16 | digest[2] << 8 | digest[3]) % 10000
var eligible = bucket < rollout_percent * 100
```

**Selección delta vs full:**
Usar delta solo si TODAS:
1. force_full=false
2. from_build_id coincide con build actual confirmado
3. Platform y arch coinciden
4. touches_bootstrap=false
5. deleted_paths vacío
6. Tamaño patch ≤ 70% del full
7. Menos de 2 patch PCK activos
8. Base confirmada pasa validación local

Caso contrario → full_artifact.

**Descarga con resume:**
1. Crear `user://updates/staging/<artifact_id>.part`
2. Leer sidecar `<artifact_id>.state.json` con chunks completados
3. Re-verificar chunks marcados como completos (SHA-256)
4. Descargar chunks faltantes con HTTP Range: `Range: bytes=start-end`
5. Si el servidor no soporta Range, reiniciar descarga secuencial
6. Validar SHA-256 de cada chunk antes de marcarlo completo
7. Al completar, validar SHA-256 del artifact entero
8. Promover con rename atómico a `user://updates/packages/<artifact_id>.pck`
9. Nunca cargar desde staging/

Retries: máximo 3 intentos por chunk, backoff 1/3/10 segundos.

**Estado local (user://updates/):**
- `installation_id` — 128 bits aleatorios, una vez
- `state.json` — accepted_sequences, active_package_ids
- `pending_boot.json` — manifest_id, build_id, package_ids, attempts
- `confirmed_boot.json` — build confirmado

**Orden de arranque (UpdateManager como primer autoload):**
1. Cargar estado local
2. Si existe pending, incrementar attempts antes de cargar
3. Si attempts > 2, desactivar pending y volver al confirmado
4. Verificar SHA-256 de cada package a cargar
5. Cargar full base + patches en orden con ProjectSettings.load_resource_pack(path, true)
6. Continuar con resto de autoloads
7. Menú principal llama confirm_boot()

confirm_boot(): pending → confirmed, guarda anterior para rollback, limpia packages fuera de retención.

**Aplicación desktop:**
- Descargar full o delta
- Pedir confirmación antes de reiniciar
- Guardar estado de gameplay si es necesario
- Nunca reiniciar en medio del gameplay sin acción del usuario

**Android:**
- kind=apk, validar SHA-256 antes de abrir installer
- No cargar PCK descargados como update de producción

**HTML5:**
- La shell obtiene y verifica el sobre con Web Crypto
- Al aceptar, navega con cache busting: `?build_id=<signed_build_id>`
- Service worker debe invalidar por build_id

**iOS:**
- No instalar artifacts desde el juego
- Mostrar release y abrir TestFlight/App Store

**Compactación:**
- Máx 2 patch PCK activos sobre un full
- Tercer update debe usar full
- Staging > 7 días se limpia al iniciar

### VersionChecker (modify)
Mantener compatibilidad temporal. Proyectar has_update, latest_version_data y señal new_version_available desde UpdateManager. No mantener dos HTTP checks independientes.

### Tests (test_update_manifest_v2.gd)
Unit tests en GDScript Godot 3.6:
- Firma válida y payload exacto
- Payload alterado → rechazo
- Firma alterada/truncada → rechazo
- key_id desconocido, expirado, no vigente → rechazo
- Canal distinto, plataforma distinta → rechazo
- Secuencia menor, igual → rechazo, mayor → acepta
- Rollback firmado con secuencia mayor → acepta
- Rollout bucket dentro/fuera → correcto
- Delta elegible vs no elegible (7 condiciones)
- Download resume: corte + resume
- Chunk corrupto → rechazo
- Pending boot → carga exitosa
- Pending falla 2 veces → rollback a confirmado
