# FD-247: Cargol Defensivo — Pulso EMP y Soporte Cinético

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-07-26
**Depends on:** FD-245 (DDC Containment Drone)

## Problem

En el diseño cinético del Acto I (estilo Robotron), Cargol deja de ser un dron de puzzle pasivo y necesita ser una herramienta defensiva activa. El jugador está en movimiento perpetuo, los DDC lo persiguen, y Cargol es su única ventaja táctica.

El diseño actual (FD-241) lo concibe como compañero que sigue, ilumina y activa botones. Para la visión arcade, Cargol necesita ser un "segundo joystick" — ofensivo, reactivo, que el jugador usa sobre la marcha sin detenerse.

## Solution

Cargol como herramienta defensiva con dos capacidades: pulso EMP (ataque) y distracción/señuelo (control de aggro). Se controla con un solo botón contextual, sin menús.

### Comportamiento base (siempre activo)

- **Sigue al jugador** a ~2m de distancia, flotando a la altura del hombro.
- **Luz de estado pasiva:** azul tenue. Cambia según contexto (ver abajo).
- **Sin colisión con el jugador:** es un fantasma para Elías, solo colisiona con geometría.
- **Audio:** zumbido suave característico que permite ubicarlo sin mirarlo.

### Habilidad 1: Pulso EMP

- **Input:** un botón dedicado (ej: E o clic medio). Sin apuntar — es omnidireccional.
- **Efecto:** pulso esférico de energía que se expande desde Cargol (~5m radio). Atraviesa geometría.
- **Sobre DDC:** los aturde 3-4 segundos (estado STUNNED). Luz del DDC se apaga, cae 0.5m (pierde sustentación breve), zumbido débil.
- **Cooldown:** 8 segundos. Indicado en HUD con barra circular.
- **Visual:** onda de choque azul/blanca que se expande y disipa. Partículas de chispas.
- **Audio:** pulso grave + chisporroteo eléctrico.
- **Luz de Cargol durante cooldown:** ámbar parpadeante → vuelve a azul cuando está listo.

### Habilidad 2: Señuelo (Attract)

- **Input:** mantener el mismo botón EMP 1s (carga). Cargol emite un tono creciente durante la carga.
- **Efecto:** Cargol se desplaza al punto donde apunta la cámara (raycast al mundo) y emite un pulso de "falsa firma de Elías". Todos los DDC en rango repriorizan a Cargol como objetivo por 5 segundos.
- **Durante el señuelo:** Cargol se vuelve vulnerable. Si un DDC lo toca, entra en STUNNED (el propio Cargol queda inactivo 6s, luz roja, caído al suelo).
- **Visual:** Cargol proyecta un holograma fantasma de Elías corriendo en dirección opuesta. Ligero flicker.
- **Audio:** tono agudo de "cebo" + zumbido de proyección holográfica.
- **Cooldown:** 15 segundos (compartido con EMP — usar uno inicia cooldown del otro).

### Estados de Cargol

| Estado | Luz | Comportamiento |
|--------|-----|---------------|
| IDLE | Azul tenue | Sigue al jugador |
| EMP_CHARGING | Ámbar pulsante | Cargando pulso (0.3s anticipación) |
| EMP_FIRING | Blanco brillante | Onda expansiva |
| EMP_COOLDOWN | Ámbar parpadeo lento | Sin habilidades, sigue al jugador |
| LURE_DEPLOYED | Verde pulsante | En posición de señuelo, proyectando holograma |
| STUNNED | Rojo, apenas visible | En el suelo, inactivo 6s |
| RETURNING | Cian | Volviendo al jugador después de señuelo |

### Control contextual

Un solo botón, dos comportamientos:
- **Tap (≤0.3s):** Pulso EMP (si no está en cooldown).
- **Hold (>0.8s):** Carga de señuelo. Se cancela si el jugador suelta antes de completar la carga.

Esto mantiene los controles simples — el jugador no necesita recordar combinaciones.

### HUD de Cargol

- **Icono de Cargol** esquina inferior derecha, discreto.
- **Barra de cooldown** circular alrededor del icono. Se llena en sentido horario.
- **Indicador de estado:** color del icono = color de la luz de Cargol.
- **Texto breve** al cambiar de estado: "EMP LISTO", "SEÑUELO ACTIVO", "CARGOL CAÍDO".

### Arquitectura técnica

```gdscript
# core_v2/actors/CargolDefensiveV1.gd
extends KinematicBody

enum State { IDLE, EMP_CHARGING, EMP_FIRING, EMP_COOLDOWN, LURE_DEPLOYED, STUNNED, RETURNING }

var state = State.IDLE
var player: NodePath
var cooldown_timer: float = 0.0
var stun_timer: float = 0.0
var emp_cooldown: float = 8.0
var lure_cooldown: float = 15.0
var emp_radius: float = 5.0
var lure_duration: float = 5.0
var stun_duration: float = 6.0
var follow_distance: float = 2.0

func fire_emp() -> void:
    pass

func deploy_lure(target_position: Vector3) -> void:
    pass

func _follow_player(delta: float) -> void:
    pass
```

### Considered Options

- **Option A**: Cargol como herramienta defensiva con EMP + señuelo, un botón contextual — **Selected**. Simple, arcade, sin menús. Encaja con movimiento perpetuo.
- **Option B**: Cargol con múltiples habilidades en radial menu — descartado, requiere detenerse, rompe el flow cinético.
- **Option C**: Cargol solo estético (sigue y reacciona, sin habilidades) — descartado, no aporta al gameplay.

### Relación con FD-241 (Cargol V2)

FD-247 **reemplaza** la Etapa B de FD-241 (compañero funcional). La Etapa A (AgentBase) puede mantenerse si es útil, pero Cargol ya no necesita follow IA compleja — el follow básico es trivial y no justifica una jerarquía de herencia. Si AgentBase ya existe, CargolDefensiveV1 puede heredar de él; si no, es standalone.

### No en este FD (backlog)

- Activar botones/pedestales a distancia (puzzle, no arcade)
- Iluminación de entorno (Cargol linterna)
- Modo cámara de Cargol (scouting)
- Habilidades avanzadas (campo de ralentización, sobrecarga de consolas)

## Files to Modify

- `core_v2/actors/CargolDefensiveV1.gd` (nuevo) — lógica principal
- `core_v2/actors/CargolDefensiveV1.tscn` (nuevo) — escena con mesh, luces, partículas
- `core_v2/ui/CargolHUD.gd` (nuevo) — HUD de cooldown y estado
- `core_v2/ui/CargolHUD.tscn` (nuevo)
- `core_v2/tests/test_cargol_emp.gd` (nuevo)
- `core_v2/tests/test_cargol_lure.gd` (nuevo)

## Verification

1. Cargol sigue al jugador a 2m de distancia, flotando
2. Tap de botón → pulso EMP → DDC en rango quedan STUNNED 3-4s
3. Hold de botón → Cargol se desplaza a punto mirado → DDC repriorizan a Cargol
4. Señuelo dura 5s, luego Cargol vuelve con el jugador
5. Cooldown EMP (8s) y señuelo (15s) se muestran en HUD
6. Cargol alcanzado por DDC durante señuelo → STUNNED 6s
7. Luz de Cargol refleja estado correctamente en todos los estados
8. Controles con un solo botón, tap vs hold funcionan sin ambigüedad
9. Deterministic replay compatible
10. Cargol no interfiere con movimiento, salto ni interacción del jugador
