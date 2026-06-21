# FD-228 / Etapa 3 — Central Endpoint para updates

## Contexto
FD-228 define un sistema de actualización segura. Esta etapa implementa el endpoint `/game/updates/v1/manifest` en Odisea Central.

## Archivos a modificar
- `odisea_central.py` (modify)
- Tests Python existentes del central o archivo específico equivalente

## Requerimientos

### Endpoint
```http
GET /game/updates/v1/manifest?channel=release&platform=linux&arch=x86_64&current_version=0.3.2&current_build_id=12345&installation_bucket=7421
```

Parámetros requeridos: channel, platform, arch, current_version, current_build_id.
Parámetro opcional: installation_bucket.

Headers:
```
Accept: application/vnd.odisea.update-manifest.v1+json
If-None-Match: "manifest-etag-opcional"
```

No se envían installation_id, player ID, token de telemetría ni datos personales.

### Responses

| HTTP | Significado | Body |
|---:|---|---|
| 200 | Existe manifiesto candidato | Sobre firmado (raw, sin modificar) |
| 204 | No hay versión posterior aplicable | Vacío |
| 304 | ETag del manifiesto no cambió | Vacío |
| 400 | Parámetros inválidos | Error JSON |
| 409 | Cliente debajo de min_supported_version | Sobre firmado con force_full=true |
| 503 | Origen no disponible + sin cache | Error JSON |

### Cache
- Cache key: (channel, platform, arch, current_build_id)
- TTL normal: 300 segundos (5 min)
- stale-if-error de hasta 24 horas solo si el sobre cacheado no expiró todavia
- ETag = SHA-256 de los bytes del sobre
- Límite del sobre: 2 MiB
- Validar JSON y límites de tamaño, pero devolver exactamente el sobre publicado

### Fuente de datos
El central obtiene los manifiestos desde GitHub Releases del repo icarito/Odisea. La metadata de releases se cachea. No se genera ni modifica el contenido del sobre firmado.

### Mantener compatibilidad
- `/game/version` sigue operativo durante la migración de FD-225

### Tests
Cubrir: 200, 204, 304, 400, 409, 503. Verificar que el payload servido es byte-a-byte igual al publicado.

### Consideraciones de seguridad
- Validar que channel solo acepte "release" o "nightly"
- Validar platform contra lista conocida
- No permitir inyección en parámetros
- Los errores no firmados nunca pueden ordenar una actualización
