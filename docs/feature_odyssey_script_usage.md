# OdysseyScript (OYS) — Guía de Uso

OdysseyScript (OYS) es un lenguaje de alto nivel diseñado para describir secuencias de acciones de jugador en Odisea, permitiendo generar replays deterministas y pruebas automatizadas.

## ¿Para qué sirve?
- Crear replays reproducibles para testeo y debugging.
- Escribir pruebas de determinismo para el motor y agentes.
- Documentar y automatizar secuencias de juego.

## Estructura básica de un script OYS
```oys
// Comentario: Descripción del test
SET pos (0, 0, 0)      // Posición inicial
SET rot 0              // Rotación inicial

SECTION "Nombre de la sección"
    FW 2.0             // Avanzar 2 segundos
    WAIT 0.2           // Pausa breve
    JUMP 0.3           // Saltar, mantener 0.3s
    FW 1.0             // Avanzar 1 segundo
    ASSERT pos.z > 2 "El jugador no avanzó suficiente"
END
```

## Comandos principales
- `FW <segundos>`: Avanza hacia adelante.
- `BW <segundos>`: Retrocede.
- `LT <grados>`: Gira a la izquierda.
- `RT <grados>`: Gira a la derecha.
- `LOOK <grados>`: Mueve la cámara verticalmente.
- `JUMP <segundos>`: Salta (mantiene el botón).
- `INTERACT`: Interactúa (un frame).
- `WAIT <segundos>`: Espera sin input.
- `SET <propiedad> <valor>`: Fija estado inicial.
- `ASSERT <condición> "mensaje"`: Verifica condición al final.
- `SECTION "nombre" ... END`: Agrupa acciones y asserts.

## Modificadores avanzados
- `AT <segundos> <acción>`: Ejecuta una acción en un frame específico dentro de otra acción.

## Ejemplo completo
```oys
// Test de salto y avance
SET pos (0, 0, 0)
SET rot 0

SECTION "Salto y avance"
    FW 1.0
    JUMP 0.2 AT 0.5 FW 0.5 // Salta a los 0.5s mientras avanza
    WAIT 0.3
    ASSERT pos.z > 1.5 "No avanzó lo suficiente"
END
```


## Cómo ejecutar y reproducir un script OYS
1. Guarda tu script en `core_v2/tests/mi_test.oys`.
2. (Opcional) Genera el JSON:
    ```sh
    godot3-bin --no-window --script ./core_v2/utils/OYSRunner.gd ./core_v2/tests/mi_test.oys
    ```
    Esto genera `mi_test.json` con el buffer de inputs.
3. Para pruebas de determinismo (ambos formatos):
    ```sh
    ./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd
    ```
    El test detecta y ejecuta automáticamente todos los `.oys` y `.json`.
4. Para ver el replay en vivo:
    ```sh
    godot3-bin ./core_v2/scenes/TestScene_v2.tscn --replay ./core_v2/tests/mi_test.oys
    ```
    O también puedes usar un `.json`:
    ```sh
    godot3-bin ./core_v2/scenes/TestScene_v2.tscn --replay ./core_v2/tests/mi_test.json
    ```

Ambos formatos son soportados de forma transparente por el motor y los tests.

## Buenas prácticas
- Usa comentarios (`// ...`) para documentar cada test.
- Agrupa acciones en `SECTION` para claridad y organización.
- Usa `ASSERT` para validar resultados esperados.
- Mantén los scripts cortos y enfocados en una mecánica o caso de uso.

## Referencia rápida
| Comando   | Descripción                  |
|-----------|-----------------------------|
| FW        | Avanza                      |
| BW        | Retrocede                   |
| LT/RT     | Gira                        |
| LOOK      | Mueve cámara                |
| JUMP      | Salta                       |
| INTERACT  | Interactúa                  |
| WAIT      | Pausa                       |
| SET       | Estado inicial              |
| ASSERT    | Verifica condición          |
| SECTION   | Agrupa acciones             |
| AT        | Acción en frame específico  |

---
Para más detalles, consulta AGENTS.md y los ejemplos en `core_v2/tests/`.
