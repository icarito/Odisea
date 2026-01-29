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
- `FW <valor>`: Avanza. Valor puede ser segundos (ej: `2.0s`) o metros (ej: `5m`). Por defecto segundos.
- `BW <valor>`: Retrocede.
- `LEFT <valor>`: Gira a la izquierda si es un número (ej: `90`) o desliza a la izquierda si tiene unidad (ej: `2s`, `5m`).
- `RIGHT <valor>`: Gira o desliza a la derecha.
- `LT <valor>`: Sinónimo de `LEFT`.
- `RT <valor>`: Sinónimo de `RIGHT`.
- `LOOK <grados>`: Mueve la cámara verticalmente.
- `JUMP <segundos>`: Salta (mantiene el botón).
- `INTERACT`: Interactúa (un frame).
- `WAIT <segundos>`: Espera sin input.
- `SET <propiedad> <valor>`: Fija estado inicial.
- `ASSERT <condición> "mensaje"`: Verifica condición al final.
- `SECTION "nombre" ... END`: Agrupa acciones y asserts.

## Modificadores de Velocidad
- `WALK <acción>`: Fuerza a caminar (ej: `WALK FW 2s`).
- `RUN <acción>`: Fuerza a correr (ej: `RUN LEFT 5m`). Por defecto las acciones de movimiento corren.

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
