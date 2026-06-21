# FD-228 / Etapa 2 — CI Pipeline y Publicación de Manifiestos

## Contexto
FD-228 define un sistema de actualización segura. Esta etapa implementa la generación de artifacts firmados en CI y su publicación en GitHub Releases.

## Archivos a modificar/crear
- `.github/workflows/export_all.yml` (modify - add manifest generation step)
- `scripts/update_manifest.py` (new: inventario, sobre firmado, firma)

## Requerimientos

### Script: scripts/update_manifest.py
Script Python que se ejecuta en CI después de exportar builds. Debe:

1. **Escaneo de artifacts**: Recibe un directorio con los artifacts exportados y genera un inventario JSON con paths, tamaños y SHA-256.

2. **Cálculo de hashes**: SHA-256 por artifact completo y por chunks de 4 MiB (4.194.304 bytes). El último chunk puede ser menor.

3. **Generación de payload**: Construye un payload JSON UTF-8 con todos los campos requeridos:
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
  "deltas": [],
  "release_notes_url": "https://github.com/icarito/Odisea/releases/tag/v0.3.3",
  "downloads_page": "https://icarito.github.io/odisea-neon-dreams/#downloads"
}
```

4. **Firma del payload**: Usa openssl para firmar con RSASSA-PKCS1-v1_5-SHA256:
```bash
openssl dgst -sha256 -sign private.pem -out payload.sig payload.json
```

5. **Generación del sobre firmado**: Produce el sobre JSON final:
```json
{
  "schema_version": 1,
  "payload_b64": "BASE64_PAYLOAD",
  "signatures": [
    {
      "algorithm": "RSASSA-PKCS1-v1_5-SHA256",
      "key_id": "release-2026-a",
      "value_b64": "BASE64_SIGNATURE"
    }
  ]
}
```
   - payload_b64 = Base64(payload_json_bytes) con padding
   - value_b64 = Base64(firma_raw_bytes) con padding
   - La firma cubre los bytes exactos del payload decodificado, no el JSON serializado

6. **CLI interface**:
   - `update_manifest.py generate --artifacts-dir <dir> --output <manifest.json> --key <private.pem> --key-id <id>` — genera el sobre firmado
   - `update_manifest.py verify --manifest <manifest.json> --key-dir <dir>` — verifica el sobre
   - `update_manifest.py inventory --artifacts-dir <dir> --output <inventory.json>` — genera inventario sin firma

### Workflow CI: .github/workflows/export_all.yml

Modificar para que después de la exportación:

1. Ejecute `scripts/update_manifest.py generate` con los artifacts generados
2. La clave privada se lee de secrets de CI (ej: `UPDATE_SIGNING_KEY`)
3. El manifiesto firmado se sube como asset del release
4. La clave pública se publica como asset separado para auditoría
5. Solo ejecutar en pushes a main/releases (no en PRs de forks)
6. Validación: antes de firmar, correr tests unitarios y check_imports

### Tests
- `tests/test_update_manifest.py` (new unit tests):
  - Generar payload y verificar que se puede re-parsear
  - Firmar con clave de test y verificar con pública
  - Payload alterado debe fallar verificación
  - Firma con clave incorrecta debe fallar
  - Chunks de 4 MiB calculados correctamente

### Seguridad
- La clave privada NUNCA se incluye en artifacts, logs, ni PRs
- CI firma solo después de tests exitosos
- PRs de forks no tienen acceso a secrets → no firman
- El script nunca escribe la clave privada en disco como texto plano (usar env var o stdin)
