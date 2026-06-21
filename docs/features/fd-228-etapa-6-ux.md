# FD-228 / Etapa 6 — UX de actualización

## Contexto
FD-228 define un sistema de actualización segura. UpdateManager ya está implementado. Esta etapa implementa la UX de actualización: modificar VersionNotification para soportar las 3 severidades y acciones por plataforma.

## Archivos a modificar
- `core_v2/ui/VersionNotification.gd` (modify)
- Escena asociada a VersionNotification (modify, si es .tscn)
- Opcional: `core_v2/ui/VersionNotification.tscn`

## Requerimientos

### Severidades y comportamiento

| Severidad | Presentación | Puede continuar | Persistencia |
|---|---|---:|---|
| `optional` | Toast descartable | sí | No reaparece en sesión; se recuerda por manifest_id |
| `recommended` | Panel persistente con botón de cerrar | sí | Reaparece en siguiente sesión |
| `security_critical` | Modal tras guardar estado | no | Hasta actualizar o salir |

### La UI muestra
- Canal (release/nightly)
- Versión local y remota
- Tamaño estimado de descarga
- Tipo: "delta" o "completo"
- Release notes (enlace)
- Acción específica de plataforma

### Reglas UX
1. Nunca interrumpir gameplay con reinicio automático
2. security_critical espera un punto seguro, solicita guardar, y ofrece "Actualizar" o "Salir"
3. Sin red, el check falla silenciosamente (no mostrar error al usuario)
4. Un security_critical ya verificado y vigente sigue bloqueando incluso offline
5. Update fuera del rollout no se muestra al usuario
6. Rechazos criptográficos no muestran detalles técnicos al jugador; se registran en log

### Acciones por plataforma
- **Desktop**: botón "Descargar e instalar" → llama UpdateManager.begin_update(). Al completar: "Reiniciar para aplicar"
- **Android**: botón "Abrir instalador" → inicia intent del sistema con APK verificado
- **HTML5**: "Actualizar ahora" → navega con cache busting (?build_id=xxx)
- **iOS**: "Ver en App Store" → abre TestFlight/App Store

### Integración con UpdateManager
Conectar señales:
- `UpdateManager.update_available(info)` → mostrar UI según severidad
- `UpdateManager.update_progress(downloaded_bytes, total_bytes)` → barra de progreso
- `UpdateManager.update_ready(info)` → cambiar botón a "Reiniciar"
- `UpdateManager.update_failed(code, recoverable)` → mostrar error si recoverable=false

### Compatibilidad
- Mantener la señal legacy `new_version_available` proyectada desde UpdateManager
- VersionChecker ya no hace HTTP checks independientes
