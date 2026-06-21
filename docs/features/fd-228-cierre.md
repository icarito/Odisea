# FD-228 / Cierre — HTML5 shell, plataformas restantes y limpieza

## Contexto
FD-228 está 90% implementado en `feature/FD-228-secure-update-system`. Esta tarea implementa lo que falta para cerrar.

## 1. HTML5 shell (simplificado)
No necesitamos Web Crypto ni verificación criptográfica en HTML5. El build se sirve desde Netlify con HTTPS del dominio oficial.

Agregar en el código de la shell HTML5 (`shell_scripts/` o donde esté):
- Al iniciar, llamar a `/game/updates/v1/manifest?channel=release&platform=html5&arch=web&current_version=X&current_build_id=Y`
- Si 200 → parsear severidad y version
- Si severity=security_critical → bloquear con modal "Actualización de seguridad requerida"
- Si severity=recommended/optional → toast/persistente
- Al aceptar → `window.location = deployment_url + "?build_id=xxx"`
- Si 204 o error de red → ignorar silenciosamente

## 2. Platform specifics en UpdateManager
Ya está casi todo. Agregar/completar:
- **Android**: cuando kind=apk, validar SHA-256 y abrir intent del sistema. No cargar PCK.
- **iOS**: siempre mostrar enlace a TestFlight/App Store. No descargar artifacts.
- **HTML5**: delegar a la shell (no intentar descargar PCK)

La detección de plataforma usar `OS.get_name()` mapeado al formato de CI.

## 3. Limpieza
Eliminar archivos que Jules dejó de test y no deberían estar en el repo:
- `check_crypto.gd`
- `test_sig.b64`
- `test_sig.bin`
Si hay otros archivos temporales similares, eliminarlos también.

## 4. project.godot
- Verificar que UpdateManager sea el PRIMER autoload
- Agregar settings de export HTML5 si faltan (para la shell)

## NO hacer
- No implementar Web Crypto
- No modificar el pipeline CI (ya está)
- No crear nuevos archivos .md de spec
