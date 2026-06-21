# FD-228 / Etapa 7 — Endurecer comando reload_pck

## Contexto
FD-228 define un sistema de actualización segura. Esta etapa endurece el comando reload_pck en ANNAV2.

## Archivos a modificar
- `core_v2/telemetry/ANNAV2.gd` (modify)

## Estado actual
Actualmente `_cmd_reload_pck()` acepta una URL arbitraria, descarga el PCK a `user://temp_injection.pck` y lo carga sin comprobar firma ni SHA-256.

## Nuevo comportamiento

Después de FD-228, el comando reload_pck debe aceptar:

```json
{
  "action": "reload_pck",
  "args": {
    "artifact_id": "linux-x86_64-0.3.3-full",
    "scene": "res://scenes/Main.tscn"
  }
}
```

### Reglas
1. El comando NO acepta `url` como parámetro.
2. Solo acepta un `artifact_id` que exista en el estado local de updates como descargado y verificado (en `user://updates/packages/`).
3. Revalida SHA-256 antes de cargar el PCK.
4. Solo está disponible en debug/editor (no en builds release).
5. En producción, los updates se aplican mediante reinicio y el flujo de UpdateManager, no mediante este comando.
6. Si el artifact_id no existe o el hash no coincide, reportar error y no cargar.
7. El comando debe rechazar cualquier intento de pasar URL externa.

### Comportamiento en debug
- Buscar el PCK en `user://updates/packages/<artifact_id>.pck`
- Verificar SHA-256 (el hash debe estar disponible en el state local)
- Si pasa validación, cargar con ProjectSettings.load_resource_pack()
- Si falla, loguear error y no cargar

### Comportamiento en release
- Rechazar el comando inmediatamente con un mensaje claro
- No intentar cargar nada
