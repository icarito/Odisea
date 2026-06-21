# FD-228: Sistema de Actualización Seguro

**Status:** Design
**Priority:** High
**Effort:** Large
**Created:** 2026-06-21
**Completed:** -

## Problem

FD-225 permite consultar una versión remota y mostrar una notificación, pero no
implementa un sistema de actualización. El cliente actual:

- Confía en una respuesta JSON sin firma servida por `/game/version`.
- No distingue de forma contractual entre `release` y `nightly`.
- No verifica autenticidad, integridad, expiración ni orden de los releases.
- No puede reanudar descargas ni recuperar una actualización interrumpida.
- No conserva una versión confirmada para rollback.
- Solo compara una versión SemVer simplificada.
- Envía al usuario nativo a una página de descargas.

Además, `ANNAV2._cmd_reload_pck()` acepta una URL arbitraria, descarga el PCK a
`user://temp_injection.pck` y lo carga sin comprobar firma ni SHA-256. Ese
comando es útil para desarrollo, pero no constituye una frontera de confianza
válida para producción.

El pipeline unificado de FD-168 ya genera artifacts multiplataforma, metadata de
build y releases `release`/`nightly`. FD-228 debe extender esa infraestructura,
no crear un segundo pipeline de distribución.

### Objetivos

1. Ningún artifact se aplica si el manifiesto no tiene una firma válida de una
   clave conocida o si falla cualquier hash requerido.
2. Toda aplicación PCK en desktop es recuperable mediante una versión
   previamente confirmada. Android/iOS delegan rollback al mecanismo de la
   plataforma y nunca prometen rollback local.
3. Las descargas interrumpidas pueden reanudarse sin volver a descargar chunks
   ya verificados.
4. Los deltas reducen al menos 30% la mediana de bytes descargados frente al PCK
   completo cuando existe una base compatible.
5. Al menos 99% de las actualizaciones iniciadas en condiciones soportadas
   terminan aplicadas o vuelven de forma segura al build confirmado.
6. El canal, la severidad, el rollout y el target de plataforma se deciden con
   datos firmados.

## Solution

Implementar un updater por manifiestos firmados. CI será la autoridad que
construye artifacts, calcula hashes, genera deltas, firma manifiestos y publica
todo en GitHub Releases. Odisea Central actuará como catálogo/cache y devolverá
el sobre firmado sin reescribir su contenido. El cliente verificará el sobre y
tomará todas las decisiones sensibles usando exclusivamente el payload firmado.

En desktop, el updater descargará PCK completos o PCK patch a un área de
staging, los verificará, los promoverá atómicamente y los cargará durante el
próximo arranque, antes de la escena principal. Android, HTML5 e iOS usarán los
mecanismos de actualización permitidos por cada plataforma.

`VersionChecker` será sustituido gradualmente por un autoload `UpdateManager`.
`VersionNotification` se conservará y evolucionará para presentar la política
de severidad. `/game/version` seguirá operativo durante la migración de FD-225.

### Considered Options

- **Ed25519**: claves y firmas pequeñas, API moderna y buen rendimiento. Godot
  3.6 no lo expone en GDScript, por lo que exige integrar y mantener una
  implementación adicional en todos los targets.
- **RSA-PSS con SHA-256**: padding moderno para RSA. Godot 3.6 no permite
  seleccionar ni parametrizar PSS desde `Crypto.verify()`.
- **RSASSA-PKCS1-v1_5 con SHA-256 y RSA-2048**: soporte directo de Godot 3.6 en
  nativo y soporte estándar de Web Crypto en HTML5. La firma ocupa 256 bytes.
- **Selected**: RSASSA-PKCS1-v1_5 con SHA-256 y RSA-2048. Evita GDNative y
  dependencias criptográficas nuevas. Una futura migración a Ed25519 requiere
  un `schema_version` o algoritmo adicional y una ventana con firmas duales.

## Arquitectura

```text
GitHub Actions
  ├─ exporta builds/PCK/APK
  ├─ genera full artifacts y patch PCK
  ├─ calcula SHA-256 por artifact y chunk
  ├─ genera payload JSON UTF-8
  ├─ firma payload con clave privada CI
  └─ publica artifacts + manifest.json
             │
             ▼
GitHub Release versionado / tag nightly mutable
             │
             ▼
Odisea Central
  ├─ obtiene y cachea el sobre firmado sin modificarlo
  ├─ selecciona channel/platform/arch
  └─ sirve /game/updates/v1/manifest
             │
             ▼
UpdateManager / shell HTML5
  ├─ verifica firma y contrato
  ├─ aplica reglas de replay/rollback/rollout
  ├─ selecciona full o delta
  ├─ descarga y verifica chunks/artifact
  └─ solicita aplicación, instalación o recarga
```

### Fuentes de verdad

- La clave privada de firma existe solo como secret protegido de CI.
- Las claves públicas embebidas en el cliente son la raíz de confianza.
- El payload firmado es la autoridad para versión, canal, target, severidad,
  rollout, artifacts, expiración y rollback.
- GitHub Releases es el origen de artifacts.
- Odisea Central puede cachear y seleccionar sobres, pero no puede crear ni
  modificar una actualización válida.
- El estado local confirmado es la autoridad para recuperación de arranque.

## Contrato criptográfico

### Algoritmo

- Firma: `RSASSA-PKCS1-v1_5-SHA256`.
- Clave: RSA-2048, exponente público 65537.
- Hash de firma: SHA-256.
- Firma serializada: Base64 RFC 4648 con padding.
- Clave pública: PEM SubjectPublicKeyInfo.
- `key_id`: identificador opaco ASCII; no contiene la propia clave.

En CI, la firma equivale a:

```shell
openssl dgst -sha256 -sign private.pem -out payload.sig payload.json
```

En Godot nativo:

1. Decodificar `payload_b64`.
2. Calcular SHA-256 de los bytes exactos.
3. Cargar la clave pública correspondiente como `CryptoKey` pública.
4. Ejecutar
   `Crypto.verify(HashingContext.HASH_SHA256, digest, signature, public_key)`.

En HTML5, la shell importará la clave pública con Web Crypto y ejecutará
`crypto.subtle.verify()` con `RSASSA-PKCS1-v1_5` sobre los bytes exactos del
payload. `Crypto` de Godot 3.6 no está disponible en exports HTML5.

### Sobre firmado

```json
{
  "schema_version": 1,
  "payload_b64": "eyJtYW5pZmVzdF9pZCI6InJlbGVhc2UtMC4zLjMtMTIzNDYiLC4uLn0=",
  "signatures": [
    {
      "algorithm": "RSASSA-PKCS1-v1_5-SHA256",
      "key_id": "release-2026-a",
      "value_b64": "BASE64_SIGNATURE"
    }
  ]
}
```

Reglas:

1. `schema_version`, `payload_b64` y `signatures` son obligatorios.
2. La firma cubre los bytes obtenidos al decodificar `payload_b64`.
3. El cliente no vuelve a serializar ni canonicalizar el JSON antes de
   verificarlo.
4. El payload debe ser JSON UTF-8 válido y un objeto raíz.
5. Basta una firma válida de una clave aceptada.
6. Firmas con algoritmo o `key_id` desconocidos se ignoran. Si ninguna firma es
   válida, el sobre se rechaza.
7. SHA-256 de artifacts y chunks aporta integridad después de autenticar el
   manifiesto; nunca sustituye la firma.
8. Un error de Base64, JSON, tipo o campo obligatorio rechaza todo el sobre.

### Keyring y rotación

El cliente incluirá un keyring de solo lectura:

```json
{
  "release-2026-a": {
    "algorithm": "RSASSA-PKCS1-v1_5-SHA256",
    "public_key_path": "res://core_v2/update/keys/release-2026-a.pub",
    "not_before": "2026-06-21T00:00:00Z",
    "not_after": "2027-06-30T23:59:59Z"
  },
  "release-2027-a": {
    "algorithm": "RSASSA-PKCS1-v1_5-SHA256",
    "public_key_path": "res://core_v2/update/keys/release-2027-a.pub",
    "not_before": "2027-01-01T00:00:00Z",
    "not_after": "2028-06-30T23:59:59Z"
  }
}
```

Rotación normal:

1. Publicar un cliente que confía en clave activa y standby.
2. Durante al menos una release estable, firmar cada manifiesto con ambas.
3. Cambiar la clave activa de CI.
4. Dejar de usar la clave anterior solo cuando la versión mínima soportada ya
   incluya la nueva pública.

Compromiso de clave:

- Revocar el secret de CI.
- Publicar un cliente completo firmado por el mecanismo de distribución de la
  plataforma que incorpore una nueva raíz de confianza.
- No existe revocación remota segura si todos los clientes solo confían en la
  clave comprometida.

## API pública

### Request

```http
GET /game/updates/v1/manifest
    ?channel=release
    &platform=linux
    &arch=x86_64
    &current_version=0.3.2
    &current_build_id=12345
    &installation_bucket=7421
```

Parámetros:

| Campo | Requerido | Contrato |
|---|---:|---|
| `channel` | sí | `release` o `nightly` |
| `platform` | sí | `linux`, `windows`, `macos`, `android`, `html5` o `ios` |
| `arch` | sí | `x86_64`, `arm64`, `universal` o valor aprobado por CI |
| `current_version` | sí | SemVer del cliente, sin prefijo `v` |
| `current_build_id` | sí | Identificador decimal/string opaco emitido por CI |
| `installation_bucket` | no | Entero `0..9999`; hint de cache/rollout, nunca autoridad |

Headers:

```http
Accept: application/vnd.odisea.update-manifest.v1+json
If-None-Match: "manifest-etag-opcional"
```

No se envían `installation_id`, player ID, token de telemetría ni datos
personales.

### Responses

| HTTP | Significado | Body |
|---:|---|---|
| `200` | Existe manifiesto candidato | Sobre firmado |
| `204` | No hay versión posterior aplicable a channel/platform/arch | Vacío |
| `304` | El ETag del manifiesto candidato no cambió | Vacío |
| `400` | Parámetros inválidos o plataforma desconocida | Error no sensible |
| `409` | Cliente debajo de `min_supported_version` | Sobre firmado con `force_full=true` |
| `503` | GitHub/origen no disponible y no existe cache utilizable | Error no sensible |

Ejemplo de error:

```json
{
  "error": "invalid_platform",
  "message": "Unsupported platform/arch pair"
}
```

Los errores no firmados nunca pueden ordenar una actualización, bloqueo,
rollback o cambio de canal.

### Cache del central

- Cache key:
  `(channel, platform, arch, current_build_id)`.
- TTL normal: 300 segundos.
- Se permite stale-if-error de hasta 24 horas solo si el sobre cacheado todavía
  no expiró.
- El central valida JSON y límites de tamaño, pero devuelve exactamente el sobre
  publicado.
- `ETag` es SHA-256 de los bytes del sobre.
- Límite del sobre: 2 MiB.
- `/game/version` sigue disponible hasta completar el rollout de FD-228.

## Payload firmado

Ejemplo completo:

```json
{
  "manifest_id": "release-0.3.3-12346",
  "channel": "release",
  "version": "0.3.3",
  "build_id": "12346",
  "release_sequence": 12346,
  "commit": "0123456789abcdef0123456789abcdef01234567",
  "issued_at": "2026-06-21T20:00:00Z",
  "expires_at": "2026-07-21T20:00:00Z",
  "severity": "optional",
  "min_supported_version": "0.3.0",
  "force_full": false,
  "rollout_percent": 100,
  "platform": "linux",
  "arch": "x86_64",
  "full_artifact": {
    "artifact_id": "linux-x86_64-0.3.3-full",
    "kind": "full_pck",
    "url": "https://github.com/icarito/Odisea/releases/download/v0.3.3/Odisea-0.3.3.pck",
    "size": 182736455,
    "sha256": "64_HEX_CHARACTERS",
    "chunk_size": 4194304,
    "chunks": [
      {
        "index": 0,
        "offset": 0,
        "size": 4194304,
        "sha256": "64_HEX_CHARACTERS"
      }
    ]
  },
  "deltas": [
    {
      "from_version": "0.3.2",
      "from_build_id": "12345",
      "artifact": {
        "artifact_id": "linux-x86_64-0.3.2-to-0.3.3-patch",
        "kind": "patch_pck",
        "url": "https://github.com/icarito/Odisea/releases/download/v0.3.3/Odisea-0.3.2-to-0.3.3.patch.pck",
        "size": 52428800,
        "sha256": "64_HEX_CHARACTERS",
        "chunk_size": 4194304,
        "chunks": []
      },
      "deleted_paths": [],
      "touches_bootstrap": false
    }
  ],
  "release_notes_url": "https://github.com/icarito/Odisea/releases/tag/v0.3.3",
  "downloads_page": "https://icarito.github.io/odisea-neon-dreams/#downloads"
}
```

### Campos obligatorios

| Campo | Tipo | Regla |
|---|---|---|
| `manifest_id` | string | Único e inmutable; máximo 128 caracteres |
| `channel` | string | Debe coincidir exactamente con el canal local |
| `version` | string | SemVer válido |
| `build_id` | string | ID emitido por CI |
| `release_sequence` | integer | Positivo y monotónico por canal |
| `commit` | string | SHA Git completo de 40 hex |
| `issued_at` | string | UTC RFC 3339 |
| `expires_at` | string | UTC RFC 3339 posterior a `issued_at` |
| `severity` | string | `optional`, `recommended`, `security_critical` |
| `min_supported_version` | string | SemVer válido |
| `force_full` | bool | Prohíbe seleccionar delta |
| `rollout_percent` | integer | `0..100` |
| `platform` | string | Debe coincidir con plataforma local normalizada |
| `arch` | string | Debe coincidir con arquitectura local |
| `full_artifact` | object | Artifact completo válido |
| `deltas` | array | Puede estar vacío |
| `release_notes_url` | string | HTTPS allowlisted |
| `downloads_page` | string | HTTPS allowlisted |

Campos desconocidos se ignoran para permitir extensiones compatibles dentro del
mismo schema. Cambiar el significado o tipo de un campo existente requiere un
nuevo `schema_version`.

### Validación temporal

- Tolerancia de reloj: ±10 minutos.
- Rechazar si `issued_at` está más de 10 minutos en el futuro.
- Rechazar si `expires_at` ya pasó, salvo cache local usada exclusivamente para
  completar o revertir un update ya descargado y verificado.
- Releases: vigencia normal máxima de 90 días.
- Nightly: vigencia normal máxima de 7 días.

## Versiones, canales y rollback

### Canal local

El canal se obtiene de build metadata:

- Build oficial desde branch/release estable: `release`.
- Build desde `main` o prerelease manual: `nightly`.
- Build local sin metadata: `nightly`.

No se permite:

- Fallback silencioso de `release` a `nightly`.
- Cambiar de canal mediante respuesta del servidor.
- Aplicar un manifiesto cuyo `channel` no coincida con el canal local.

Un cambio manual de canal, si se agrega en tooling de desarrollo, debe estar
limitado a builds debug/editor y no forma parte de la UX de producción.

### Comparación

- `release_sequence` decide frescura y defensa anti-replay.
- `version` cumple SemVer 2.0.0, se serializa sin prefijo `v` y se usa para UX
  y compatibilidad. El build metadata después de `+` no afecta precedencia.
- `build_id` identifica una base exacta para deltas.
- Un manifiesto se rechaza si su `release_sequence` es menor o igual al mayor
  valor aceptado para ese canal, salvo que su `manifest_id` sea el pending
  actualmente descargado.
- La secuencia se persiste después de validar firma, schema, canal, target y
  tiempo, incluso si el cliente queda fuera del rollout. Ampliar un rollout
  exige publicar un manifiesto nuevo con `manifest_id` y secuencia mayores,
  aunque apunte al mismo `build_id`.

### Rollback oficial

Un rollback legítimo se publica como manifiesto nuevo:

- `release_sequence` mayor que cualquier manifiesto anterior.
- `version` puede ser menor que la instalada.
- `build_id` identifica el artifact de rollback.
- `force_full=true`.
- Severidad mínima `recommended`.

Por lo tanto, una versión menor no se acepta por sí sola; solo se acepta si está
contenida en un manifiesto nuevo, firmado y monotónico.

## Rollout

El rollout autoritativo se calcula localmente:

```text
digest = SHA-256(UTF8(installation_id + ":" + manifest_id))
bucket = uint32_big_endian(digest[0:4]) % 10000
eligible = bucket < rollout_percent * 100
```

- `installation_id` es un valor aleatorio de 128 bits creado una vez y guardado
  en `user://updates/installation_id`.
- No contiene player ID, username, hardware ID ni datos de telemetría.
- Si falta o está corrupto, se genera uno nuevo con RNG criptográfico.
- El `installation_bucket` enviado al endpoint es solo un hint opcional. Como el
  cliente no conoce necesariamente el próximo `manifest_id`, puede omitirse o
  enviar el bucket del último manifiesto visto.
- El cliente siempre recalcula el bucket con el `manifest_id` firmado. El
  servidor no puede declarar elegible a un cliente que falla esa condición.
- `security_critical` puede usar rollout menor a 100 durante canary, pero no
  bloquea clientes fuera del rollout.
- Cambiar `rollout_percent`, severidad o cualquier otra política requiere un
  nuevo sobre con `manifest_id` y `release_sequence` mayores. Un
  `manifest_id` publicado es inmutable.

## Artifacts, chunks y deltas

### Contrato de artifact

```json
{
  "artifact_id": "linux-x86_64-0.3.3-full",
  "kind": "full_pck",
  "url": "https://github.com/.../Odisea-0.3.3.pck",
  "size": 182736455,
  "sha256": "64_HEX_CHARACTERS",
  "chunk_size": 4194304,
  "chunks": [
    {
      "index": 0,
      "offset": 0,
      "size": 4194304,
      "sha256": "64_HEX_CHARACTERS"
    }
  ]
}
```

Reglas:

- `kind`: `full_pck`, `patch_pck`, `apk`, `web_deployment` o `external`.
- `url`: HTTPS y host allowlisted (`github.com`,
  `objects.githubusercontent.com`, host oficial de Odisea).
- `size`: entero positivo; máximo configurable por plataforma.
- `sha256`: lowercase hex de 64 caracteres.
- `chunk_size`: 4 MiB para artifacts mayores a 4 MiB.
- Los chunks cubren el artifact completo, en orden, sin gaps ni solapamientos.
- El último chunk puede ser menor.
- Para artifacts de hasta 4 MiB, `chunks` puede contener un único chunk.

### Descarga y resume

1. Crear `user://updates/staging/<artifact_id>.part`.
2. Leer sidecar `<artifact_id>.state.json`.
3. Verificar de nuevo cada chunk marcado como completo.
4. Descargar rangos faltantes con `Range: bytes=start-end`.
5. Si el origen no soporta Range, reiniciar una descarga secuencial completa.
6. Validar SHA-256 de cada chunk antes de marcarlo completo.
7. Al completar, validar tamaño y SHA-256 del artifact entero.
8. Promover con rename atómico a
   `user://updates/packages/<artifact_id>.pck` o extensión correspondiente.
9. Nunca cargar archivos desde `staging`.

Retries:

- Máximo 3 intentos por chunk.
- Backoff de 1, 3 y 10 segundos.
- Un hash inválido elimina solo el chunk afectado cuando sea posible.
- Tres fallos de integridad cancelan el update y registran error; no se intenta
  aplicar.

Antes de descargar, exigir espacio libre estimado:

```text
artifact.size + tamaño_del_package_confirmado + 128 MiB
```

Si la plataforma no permite consultar espacio libre de manera fiable, intentar
la escritura y tratar el error como `insufficient_storage`.

### Delta

Un delta es un PCK patch exportado por Godot que contiene solo recursos nuevos
o modificados respecto de un `from_build_id` exacto. Los chunks permiten resume
y verificación; no son un algoritmo de diff binario.

Contrato:

```json
{
  "from_version": "0.3.2",
  "from_build_id": "12345",
  "artifact": {
    "artifact_id": "linux-x86_64-0.3.2-to-0.3.3-patch",
    "kind": "patch_pck",
    "url": "https://github.com/.../update.patch.pck",
    "size": 52428800,
    "sha256": "64_HEX_CHARACTERS",
    "chunk_size": 4194304,
    "chunks": []
  },
  "deleted_paths": [],
  "touches_bootstrap": false
}
```

Seleccionar delta únicamente si:

1. `force_full=false`.
2. `from_build_id` coincide exactamente con el build confirmado.
3. Plataforma y arquitectura coinciden.
4. `touches_bootstrap=false`.
5. `deleted_paths` está vacío.
6. El tamaño del patch es menor o igual a 70% del full artifact.
7. Hay menos de dos patch PCK activos.
8. La base confirmada y sus packages pasan validación local.

Si cualquier condición falla, seleccionar `full_artifact`. No encadenar deltas
desde un build pending o no confirmado.

### Eliminaciones

Godot puede superponer archivos de packs posteriores, pero un patch no elimina
recursos existentes de un pack anterior. Por eso:

- Un release con archivos eliminados no es elegible para delta v1.
- CI debe detectar paths eliminados al comparar inventarios.
- `deleted_paths` no vacío obliga `force_full=true`.

### Límite y compactación

- Máximo dos patch PCK activos sobre un full PCK confirmado.
- El tercer update debe usar full PCK.
- Un full PCK nuevo reemplaza la cadena anterior después de confirmar boot.
- Mantener como máximo:
  - package confirmado actual;
  - package confirmado anterior;
  - package pending;
  - chunks necesarios para una descarga activa.

Staging incompleto y cache huérfano con más de siete días se elimina al iniciar,
sin tocar packages confirmados.

## Estado local

Directorio:

```text
user://updates/
  installation_id
  state.json
  pending_boot.json
  confirmed_boot.json
  keys/                 # reservado; no permite agregar raíces remotas en v1
  staging/
  packages/
```

`state.json`:

```json
{
  "schema_version": 1,
  "accepted_sequences": {
    "release": 12346,
    "nightly": 9811
  },
  "dismissed_manifest_id": "",
  "last_check_at": "2026-06-21T20:30:00Z",
  "active_package_ids": ["linux-x86_64-0.3.3-full"]
}
```

`pending_boot.json`:

```json
{
  "manifest_id": "release-0.3.3-12346",
  "build_id": "12346",
  "package_ids": ["linux-x86_64-0.3.3-full"],
  "attempts": 0,
  "created_at": "2026-06-21T20:31:00Z"
}
```

`confirmed_boot.json`:

```json
{
  "manifest_id": "release-0.3.2-12345",
  "build_id": "12345",
  "package_ids": ["linux-x86_64-0.3.2-full"],
  "confirmed_at": "2026-06-20T10:00:00Z"
}
```

Todos los archivos se escriben primero como `.tmp`, se sincronizan/cierra el
archivo y se renombran. Si un JSON está corrupto:

- No aplicar el pending.
- Conservar packages.
- Arrancar con el package confirmado detectable.
- Registrar el error sin borrar saves ni settings.

## Aplicación y recuperación

### Orden de arranque desktop

`UpdateManager` será el primer autoload:

1. Cargar y validar estado local.
2. Si existe pending, incrementar `attempts` antes de cargarlo.
3. Si `attempts > 2`, desactivar pending y volver al confirmado.
4. Verificar SHA-256 de cada package que va a cargarse.
5. Cargar full base y luego patches, en orden, con
   `ProjectSettings.load_resource_pack(path, true)`.
6. Continuar con el resto de autoloads y la escena principal.
7. Al llegar establemente al menú principal, llamar
   `UpdateManager.confirm_boot()`.

`confirm_boot()`:

- Convierte pending en confirmado.
- Conserva el confirmado anterior para rollback.
- Limpia packages fuera de retención.
- No se llama desde `_ready()` del propio autoload; el menú principal debe
  confirmar que el juego alcanzó un estado utilizable.

Un PCK cargado no puede descargarse de forma segura durante el proceso. Aplicar
o revertir requiere reiniciar.

### Bootstrap

El bootstrap comprende:

- `UpdateManager`.
- Verificador criptográfico y keyring.
- Código de lectura de estado y carga temprana de PCK.
- Shell HTML5 de update.

Un patch PCK no puede modificar bootstrap. CI debe marcar
`touches_bootstrap=true` al detectar esos paths y forzar package completo o
instalador externo. Actualizar el binario/plantilla de Godot está fuera de
alcance.

### Comando `reload_pck`

Después de FD-228:

```json
{
  "action": "reload_pck",
  "args": {
    "artifact_id": "linux-x86_64-0.3.3-full",
    "scene": "res://scenes/Main.tscn"
  }
}
```

Reglas:

- El comando no acepta `url`.
- Solo acepta un `artifact_id` presente en el estado local como descargado y
  verificado.
- Revalida SHA-256 antes de cargar.
- Solo está disponible en debug/editor.
- Producción aplica updates mediante reinicio y flujo de `UpdateManager`.

## Comportamiento por plataforma

| Plataforma | Check/verificación | Aplicación |
|---|---|---|
| Linux x86_64/arm64 | Godot `Crypto.verify()` | Full/patch PCK al reiniciar |
| Windows x86_64 | Godot `Crypto.verify()` | Full/patch PCK al reiniciar |
| macOS universal | Godot `Crypto.verify()` | Full/patch PCK al reiniciar |
| Android | Godot `Crypto.verify()` | APK completo firmado; intent del sistema |
| HTML5 | Web Crypto en shell | Recarga deployment con cache busting |
| iOS | Verificación informativa/backend store | TestFlight/App Store |
| Desconocida | Si existe verificador soportado | Solo enlace de descarga |

### Desktop

- Descargar full o delta.
- Pedir confirmación antes de reiniciar.
- Preservar momentum/estado de gameplay guardando mediante sistemas existentes;
  nunca reiniciar en medio del gameplay sin acción del usuario.
- No reemplazar ejecutable ni librerías nativas.

### Android

- Artifact `kind=apk`.
- Validar manifiesto y SHA-256 antes de abrir el installer.
- El APK debe conservar package ID y firma Android compatibles.
- La aceptación final pertenece al sistema operativo.
- No cargar scripts/PCK descargados como actualización de producción.

### HTML5

- La shell obtiene y verifica el sobre mediante Web Crypto.
- No reemplaza WASM ni PCK durante una ejecución.
- Al aceptar, navega al deployment oficial con query de cache busting:
  `?build_id=<signed_build_id>`.
- El service worker/cache debe invalidar por `build_id`.
- Si Web Crypto no está disponible, mostrar enlace/recarga convencional y no
  tratar el manifiesto como verificado.

### iOS

- No instalar artifacts desde el juego.
- Mostrar release disponible y abrir TestFlight/App Store.
- `security_critical` puede bloquear el gameplay solo si el mandato firmado fue
  validado por un componente disponible en el build; en caso contrario, usar
  política de la store.

## Política UX

| Severidad | Presentación | Puede continuar | Persistencia |
|---|---|---:|---|
| `optional` | Toast descartable | sí | No reaparece en sesión; puede recordarse por `manifest_id` |
| `recommended` | Toast persistente/panel | sí | Reaparece en siguiente sesión |
| `security_critical` | Modal tras guardar estado | no | Hasta actualizar o salir |

La UI muestra:

- canal;
- versión local y remota;
- tamaño estimado;
- tipo `delta` o `completo`;
- release notes;
- acción específica de plataforma.

Reglas:

- Nunca interrumpir gameplay con un reinicio automático.
- Un `security_critical` espera un punto seguro, solicita guardado y ofrece
  `Actualizar` o `Salir`.
- Sin red, el check falla de forma silenciosa.
- Excepción offline: un mandato `security_critical` ya verificado, vigente y
  aplicable sigue bloqueando. Un error de red nuevo nunca crea ese bloqueo.
- Un update fuera del rollout no se muestra.
- Rechazos criptográficos no muestran detalles técnicos al jugador; se
  registran para diagnóstico.

## Interfaces del cliente

API pública mínima de `UpdateManager`:

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

Estados:

```text
idle
checking
available
downloading
verifying
ready_to_restart
applying_external
blocked_critical
failed
```

`VersionChecker` conserva temporalmente:

- `has_update`.
- `latest_version_data`.
- señal `new_version_available`.

Durante compatibilidad, esos valores se proyectan desde `UpdateManager`; no se
mantienen dos HTTP checks independientes.

Códigos de error estables:

```text
network_unavailable
invalid_response
unknown_schema
unknown_key
invalid_signature
manifest_expired
channel_mismatch
platform_mismatch
replay_rejected
not_in_rollout
insufficient_storage
download_failed
chunk_hash_mismatch
artifact_hash_mismatch
state_corrupt
load_pack_failed
external_install_failed
```

## Seguridad adicional

- HTTPS es obligatorio, pero no sustituye firma.
- URLs solo pueden usar hosts allowlisted.
- No seguir redirects hacia un host no allowlisted.
- Nunca ejecutar scripts del manifiesto ni aceptar comandos arbitrarios.
- Limitar longitudes, cantidades de chunks y tamaños antes de reservar memoria.
- Máximo 16.384 chunks por artifact.
- Procesar hashes en streaming; no cargar artifacts completos en RAM.
- No registrar firmas completas, claves, installation ID ni URLs con tokens.
- La clave privada nunca se incluye en artifacts ni logs.
- Secrets de firma no están disponibles en workflows de pull requests de forks.
- CI firma únicamente después de tests y validación de imports.

## Files to Modify

### Etapa 1 — Contrato y criptografía

- `core_v2/update/UpdateManifestVerifier.gd` (new)
- `core_v2/update/UpdateKeyring.gd` (new)
- `core_v2/update/keys/*.pub` (new)
- `scripts/update_manifest.py` (new: inventario, sobre, firma y verificación)
- `core_v2/tests/test_update_manifest_v2.gd` (new)
- `tests/test_update_manifest.py` (new)

### Etapa 2 — CI y artifacts

- `.github/workflows/export_all.yml` (modify)
- `scripts/update_manifest.py` (modify)
- Archivo de inventario generado por build dentro de los assets del release

### Etapa 3 — Central

- `odisea_central.py` (modify)
- Tests Python existentes del central o archivo específico equivalente

### Etapas 4–6 — Cliente y UX

- `core_v2/systems/VersionChecker.gd` (compatibility modify)
- `core_v2/update/UpdateManager.gd` (new autoload)
- `core_v2/ui/VersionNotification.gd` y su escena (modify)
- `project.godot` (autoload order)
- Shell/scripts HTML5 usados por `export_all.yml`

### Etapa 7 — Telemetría de desarrollo

- `core_v2/telemetry/ANNAV2.gd` (modify)

Los nombres exactos de tests auxiliares pueden seguir las convenciones del
repositorio, pero no se debe mover código nuevo fuera de `core_v2`.

## Plan de implementación

### Etapa 1 — Fixtures, keyring y verificador

1. Crear clave RSA de test; nunca usarla en producción.
2. Agregar fixtures de payload, firma válida, firma alterada y key IDs.
3. Implementar generador/verificador Python.
4. Implementar verificador Godot nativo.
5. Implementar fixture equivalente con Web Crypto.

Criterio de salida:

- Python, Godot nativo y Web Crypto aceptan el mismo fixture.
- Los tres rechazan payload alterado, firma truncada y clave desconocida.

### Etapa 2 — Publicación CI

1. Generar PCK completos separados del ejecutable.
2. Crear inventario de paths y hashes por build.
3. Comparar con bases soportadas y generar patch PCK.
4. Detectar eliminaciones y cambios de bootstrap.
5. Calcular chunks de 4 MiB.
6. Generar, firmar y publicar un manifiesto por target.
7. Publicar clave pública/fingerprint fuera del artifact para auditoría.

Criterio de salida:

- Un release de prueba contiene artifact completo, delta elegible y manifiesto
  verificable.
- PRs sin secrets no intentan firmar ni exponen material privado.

### Etapa 3 — Endpoint central

1. Resolver release/nightly y target solicitado.
2. Descargar/cachear el sobre sin reserializarlo.
3. Implementar status, ETag, stale-if-error y límites.
4. Mantener `/game/version`.

Criterio de salida:

- Payload servido es byte-a-byte igual al publicado.
- Tests cubren 200, 204, 304, 400, 409 y 503.

### Etapa 4 — Descarga y selección

1. Crear `UpdateManager` y estado local.
2. Integrar build metadata y normalización de plataforma.
3. Verificar sobre, secuencia, target, tiempo y rollout.
4. Seleccionar delta/full con las reglas cerradas.
5. Implementar Range, sidecar, retries y hashes.

Criterio de salida:

- Descarga interrumpida reanuda desde chunks válidos.
- Ningún artifact inválido llega a `packages/`.

### Etapa 5 — Aplicación y rollback

1. Hacer `UpdateManager` primer autoload.
2. Implementar pending/confirmed y carga temprana.
3. Confirmar desde el menú principal.
4. Forzar rollback tras dos boots fallidos.
5. Implementar compactación y retención.

Criterio de salida:

- Full y hasta dos patches arrancan en orden.
- Dos fallos restauran el confirmado sin tocar datos del usuario.

### Etapa 6 — UX y plataformas

1. Adaptar `VersionNotification`.
2. Implementar severidades y acciones.
3. Integrar APK installer, shell HTML5 y links iOS.
4. Proyectar compatibilidad FD-225.

Criterio de salida:

- Cada plataforma presenta una única acción válida.
- No existe reinicio automático durante gameplay.

### Etapa 7 — Endurecer `reload_pck`

1. Eliminar argumento URL.
2. Resolver solo artifacts verificados.
3. Revalidar hash.
4. Mantener gating debug/editor.

Criterio de salida:

- URL arbitraria se rechaza.
- Artifact inexistente o corrupto no se carga.

### Etapa 8 — Rollout

1. Builds internos con key de staging.
2. Nightly al 100%.
3. Release al 5%.
4. Release al 25%.
5. Release al 100%.

Go/no-go por escalón:

- Éxito de aplicación ≥99%.
- Rechazos criptográficos inesperados = 0.
- Rollbacks automáticos <1%.
- Sin pérdida/corrupción de saves.
- Ahorro mediano delta ≥30%; si no se alcanza, se mantiene full mientras se
  investiga sin bloquear el rollout seguro.

## Verification

### Unitarios criptográficos

1. Firma válida y payload exacto.
2. Un byte del payload alterado.
3. Firma alterada, truncada y Base64 inválido.
4. `key_id` desconocido, expirado y todavía no válido.
5. Algoritmo no permitido.
6. Dos firmas: una inválida y una válida.

### Manifiesto y decisiones

1. Schema desconocido.
2. Campo obligatorio ausente o tipo incorrecto.
3. Manifest expirado o emitido en el futuro.
4. Canal, plataforma o arquitectura distintos.
5. Secuencia menor, igual y mayor.
6. Rollback firmado con secuencia mayor.
7. Bucket dentro y fuera del rollout.
8. `security_critical` fuera del rollout no bloquea.

### Descarga

1. HTTP Range soportado y no soportado.
2. Corte después de uno o más chunks.
3. Chunk corrupto y artifact final corrupto.
4. Timeout, 404, redirect no permitido y falta de espacio.
5. Promoción atómica y recuperación de `.tmp`.
6. Limpieza de staging con más de siete días.

### Delta/full

1. Base exacta y patch ≤70%.
2. Base distinta.
3. Patch >70%.
4. Paths eliminados.
5. Bootstrap modificado.
6. Dos patches activos y tercer update.
7. Base local corrupta.

### Boot y rollback

1. Pending arranca y menú confirma.
2. Primer boot falla y reintenta.
3. Segundo boot falla y restaura confirmado.
4. Estado JSON corrupto.
5. PCK missing o con hash inválido.
6. Rollback no borra saves/settings/telemetría.

### Integración/E2E

1. CI → GitHub nightly → Central → cliente nightly.
2. CI → release versionado → Central → cliente release.
3. Central offline con cache válida y sin cache.
4. Rotación con manifiesto de firma dual.
5. Linux, Windows, macOS, Android, HTML5 e iOS.
6. Compatibilidad de `/game/version` y señal legacy durante migración.

Comandos mínimos al implementar:

```shell
./runtest.sh -a ./core_v2/tests/test_update_manifest_v2.gd
./runtest.sh
python3 -m pytest
python3 scripts/check_tracked_imports.py
python3 scripts/check_critical_import_artifacts.py
```

La validación de imports es obligatoria si CI modifica artifacts o rutas bajo la
política de assets del proyecto.

## Observabilidad

Registrar contadores agregados, sin installation ID:

- checks exitosos/fallidos;
- manifest rechazado por código;
- full vs delta seleccionado;
- bytes esperados/descargados;
- resume utilizado;
- update listo/aplicado;
- boot confirmado;
- rollback automático.

No crear un sistema de telemetría nuevo. Usar `PerformanceMonitor`/`ANNAV2`
cuando estén disponibles y logs locales como fallback. La ausencia de
telemetría nunca bloquea un update.

## Out of Scope

- Actualizar en caliente el binario o runtime de Godot.
- Descargar y ejecutar librerías nativas.
- Descargar PCK de producción arbitrarios mediante telemetría.
- Bypass de App Store, TestFlight o confirmación del installer Android.
- Migraciones automáticas de saves.
- P2P, torrents o CDN propio.
- Actualizaciones durante gameplay sin confirmación.
- Modificar o borrar partidas, settings, replays o telemetría del usuario.
- Confiar solo en HTTPS o SHA-256 sin firma.
- Cambio de canal remoto.
- Deltas binarios del PCK; v1 usa patch PCK por archivos.

## Assumptions

- FD-168 continúa siendo el único pipeline de export/release.
- Los desktop exports conservan PCK separado (`embed_pck=false`).
- CI puede acceder a una clave privada protegida para jobs autorizados.
- GitHub Releases y el host oficial soportan HTTPS y HTTP Range.
- El menú principal dispone de un punto estable para llamar `confirm_boot()`.
- Los cambios al bootstrap se distribuyen mediante package completo o
  instalador externo, no mediante patch PCK.
