# FD-245: DDC Containment Drone — Persecución Cinética

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-07-26
**Supersedes:** FD-242 (DDC Drone + Sigilo Básico), FD-029 (DDC Drone conceptual)

## Problem

El diseño anterior del DDC asumía sigilo (patrulla, cono de visión, estados de alerta). Esto contradice la realidad narrativa: Odisea es una IA que controla todos los sensores de la nave, sabe exactamente dónde está Elías. El DDC no necesita *buscarte*, va directo a por ti.

Además, el sigilo produce un ritmo lento que no encaja con la visión de juego del director: acción cinética, conservación de momentum, decisiones rápidas. El gameplay debe sentirse como Robotron 2084: movimiento perpetuo, amenazas múltiples, reflejos.

**Regla narrativa clave:** Odisea no quiere matar a Elías, quiere controlarlo. Los DDC no disparan ni dañan — contienen. Contacto = captura, no muerte.

## Solution

DDC como **enemigo de persecución cinética pura**. Sin patrulla, sin búsqueda, sin sigilo. Sabe siempre tu posición y se mueve para interceptarte.

### Comportamiento del DDC

#### Estados
- `CHARGING` — El DDC acelera hacia la posición actual del jugador. Velocidad creciente, luz azul → ámbar. Fase de "aviso" (0.5-0.8s) donde todavía es esquivar fácil.
- `INTERCEPT` — Trayectoria de colisión calculada. El DDC predice hacia dónde va el jugador y corta camino. Luz roja pulsante. Esta es la fase peligrosa.
- `STUNNED` — Cargol aplicó pulso EM. El DDC queda inmóvil 3-4 segundos, luz apagada, zumbido débil. Vulnerable. Luego reinicia en CHARGING.
- `CONTAINING` — Hizo contacto. Animación de campo de stasis sobre Elías (0.5s). Inmediatamente después → captura (delegado a FD-246).

#### Movimiento
- **Persecución con inercia:** el DDC tiene peso. No puede girar instantáneamente. Tiene radio de giro y aceleración limitada. Un jugador hábil puede hacer que dos DDC choquen entre sí cambiando de dirección bruscamente.
- **Velocidad escalonada:** 70% de la velocidad máxima del jugador en CHARGING, 95% en INTERCEPT. El jugador siempre puede superarlo corriendo en línea recta, pero no puede detenerse.
- **Altura de vuelo:** ~1.5m del suelo. Colisiona con geometría (si el jugador se mete en un ducto, el DDC rodea o espera en la entrada).

#### Múltiples DDC simultáneos
- El sistema soporta N DDC activos (empezar con 2-3, escalable).
- Spawnean de compuertas en paredes/techo con animación de activación.
- La IA Odisea los suelta progresivamente: primero 1, luego 2, luego 3.
- Cada uno es independiente, lo que crea situaciones de "encerrona" que el jugador debe leer y romper.

### Detección (simplificada)
- **Sin cono de visión.** El DDC siempre sabe la posición del jugador (la obtiene del nodo del jugador en la escena).
- Esto simplifica el código y refleja la narrativa (Odisea controla los sensores).
- El "sigilo" no existe — la defensa es moverse y usar a Cargol.

### Audio y feedback
- **Zumbido creciente** que indica proximidad y estado. El jugador sabe si un DDC está cerca sin mirarlo.
- **Luz de estado** en el dron: azul tenue (spawneando) → ámbar (CHARGING) → rojo pulsante (INTERCEPT) → apagada (STUNNED).
- **Sonido distintivo** cuando entra en INTERCEPT (alarma breve, como un "lock-on").

### Arquitectura técnica

#### Herencia de AgentBase (FD-241 Etapa A)
Si AgentBase existe, `DDCContainmentV1` hereda de él. Si no, se implementa standalone con una mini-FSM interna. El DDC actual no comparte suficiente lógica con Cargol como para forzar la dependencia.

```gdscript
# core_v2/actors/DDCContainmentV1.gd
extends KinematicBody

enum State { CHARGING, INTERCEPT, STUNNED, CONTAINING }

var state = State.CHARGING
var target: NodePath  # siempre el jugador
var speed: float
var acceleration: float
var turn_rate: float  # rad/s, limita giro
var stun_timer: float
```

#### Sistema de spawning
- `DDCSpawner.gd` — nodo de nivel que gestiona cuántos DDC activos hay, timing de spawns, y compuertas de origen.
- Configurable por sala: la primera sala del Acto I podría tener 1 DDC cada 15s, máximo 2 simultáneos. Salas posteriores escalan.

### Considered Options

- **Option A**: DDC con persecución cinética pura — **Selected**. Contacto = captura. Sin sigilo, sin patrulla. Es la visión del director.
- **Option B**: DDC híbrido (patrulla + persecución) — descartado, complica el diseño y diluye la experiencia Robotron.
- **Option C**: DDC con armas/proyectiles — descartado, Odisea no quiere dañar a Elías.

## Files to Modify

- `core_v2/actors/DDCContainmentV1.gd` (nuevo) — IA de persecución cinética
- `core_v2/actors/DDCContainmentV1.tscn` (nuevo) — escena del dron
- `core_v2/systems/DDCSpawner.gd` (nuevo) — gestión de oleadas de DDC
- `core_v2/systems/DDCSpawner.tscn` (nuevo)
- `core_v2/tests/test_ddc_pursuit.gd` (nuevo)
- `core_v2/tests/test_ddc_multi_spawn.gd` (nuevo)

## Verification

1. DDC acelera hacia el jugador en CHARGING
2. DDC predice trayectoria en INTERCEPT (no sigue, corta camino)
3. Contacto DDC-jugador → estado CONTAINING → señal `player_contained`
4. Múltiples DDC (2-3) se mueven independientemente sin colisionar entre sí
5. DDC respeta radio de giro (no gira instantáneamente)
6. Sonido y luz reflejan el estado correctamente
7. Spawner activa DDC progresivamente desde compuertas
8. DDC se recupera de STUNNED después de 3-4s
9. Deterministic replay compatible (posición DDC, estado, timer de stun)
10. DDC no puede atravesar geometría, rodea obstáculos razonablemente
