# Uso de OdysseyScript y Replays en Odisea (2026)

Odisea ahora soporta replays y pruebas de determinismo tanto desde scripts OdysseyScript (`.oys`) como desde buffers JSON (`.json`).

## 1. Escribe tu script OYS
Guarda tu secuencia en `core_v2/tests/mi_test.oys`:

```oys
// Test de salto y avance
SET pos (0, 0, 0)
SET rot 0
SECTION "Salto y avance"
    FW 1.0
    JUMP 0.2 AT 0.5 FW 0.5
    WAIT 0.3
    ASSERT pos.z > 1.5 "No avanzó lo suficiente"
END
```

## 2. (Opcional) Genera el JSON
```sh
godot3-bin --no-window --script ./core_v2/utils/OYSRunner.gd ./core_v2/tests/mi_test.oys
```
Esto genera `mi_test.json`.

## 3. Pruebas de determinismo (¡automáticas para ambos formatos!)
```sh
./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd
```
El sistema detecta y ejecuta todos los `.oys` y `.json` en `core_v2/tests/` y subcarpetas.

- Si el archivo es `.oys`, se convierte en vivo y se usa la escena `TestScene_v2.tscn` por defecto (o la que declares con `LEVEL ...`).
- Si es `.json`, se usa directamente como buffer de inputs.
- Ambos tipos de archivo validan asserts y drift.

## 4. Reproducir un replay en vivo
Puedes lanzar el juego con:
```sh
godot3-bin --main-pack project.pck --replay res://core_v2/tests/mi_test.oys
```
O con un `.json`:
```sh
godot3-bin --main-pack project.pck --replay res://core_v2/tests/mi_test.json
```

## 5. Buenas prácticas
- Usa comentarios y `SECTION` para claridad.
- Usa asserts para validar resultados esperados.
- Si tu OYS no declara `LEVEL`, se usará `TestScene_v2.tscn`.
- Puedes mezclar archivos `.oys` y `.json` en tus tests.

---

## Resumen rápido
| Acción                        | Comando/Flujo                                                                 |
|-------------------------------|------------------------------------------------------------------------------|
| Escribir test OYS             | Edita `.oys` en `core_v2/tests/`                                             |
| Generar JSON (opcional)       | `godot3-bin --no-window --script ./core_v2/utils/OYSRunner.gd archivo.oys`   |
| Ejecutar todos los tests      | `./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd`                     |
