# FD-256: Sistema Criocoolant (CryoVent)

**Status:** Design
**Priority:** High
**Effort:** Small
**Created:** 2026-08-15
**Parent:** FD-255 (Maestro)
**Assets a reutilizar:** `core_v2/systems/ice/`, `props/pipe/`, `systems/gas/`

## 1. Función y lugar físico

El criocoolant es el refrigerante criogénico que mantiene fríos los criopods. Es la "sangre
del sepulcro". Vive junto a los criopods, siempre: tuberías expuestas, radiadores, tanques
de almacenamiento, válvulas de coolant. Color **cian**.

## 2. Lenguaje visual

- Luz azul cian + niebla baja (ya es la estética base del módulo de criogenia).
- Señal de sistema sano: brillo cian constante y suave en tuberías y radiadores.

## 3. Fallo y aviso

- **Fallo:** fuga de gas frío → niebla densa que **reduce visibilidad** (no daña, ciega).
- **Aviso (patrón legible, siempre en este orden):**
  1. Condensación súbita en la tubería (gotas formándose)
  2. Gotas congelándose en el aire (cristales)
  3. Nube de niebla densa invade la sala

El jugador aprende: *condensación = sal de aquí o te quedas ciego*. Nunca daña de golpe.

## 4. Liberación (mini-game de restaurar)

**Sellar la válvula de coolant.** Reutiliza `PipeValve` (`InteractableBaseV2`): el jugador
gira la válvula (animación de 180° ya implementada) y la fuga se detiene. La niebla se
disipa. Es el respiro: sin timer agresivo, sin enemigo.

- Opcional (si hay sala grande): varias válvulas en secuencia usando `LogicCircuitManager`
  (AND de válvulas → fuga maestra se cierra).

## 5. Integración de efectos y archivos

**Problema de nombres:** `core_v2/visual/plasma_exhaust/PlasmaExhaust_D.tscn` es una pluma
**tintable genérica** (por defecto azul). Hoy se llama "plasma" pero su rol visual es el
crioenfriador.

**Acción:** renombrar la familia `PlasmaExhaust_{A,B,C,D,E}` bajo `visual/plasma_exhaust/`
a `CryoVent_{A,B,C,D,E}` y moverla a `core_v2/visual/cryo_vent/`. Ajustar las referencias
internas (paths de `PlasmaExhaust_D.gd` a `CryoVentBase.gd`). Mantener `core_color`/`hot_color`
en cian por defecto.

- **Niebla:** `systems/gas/GasArea3D` con densidad que sube/baja según la válvula. El gas
  frío no daña; solo tapa la visión (buoyancy ≈ 0, viscosidad alta).
- **Hielo (opcional, si hay derrame extenso):** `systems/ice/IceLevel` ya modela una línea
  ascendente con drenaje de integridad; reusarlo solo si queremos zonas de congelación.

**Archivos:**
- `core_v2/visual/cryo_vent/` (renombrado de `plasma_exhaust/`)
- `core_v2/systems/cryo/` (nuevo, lógica ligera de fuga de coolant) — o reusar `gas/` directamente
- `.tscn`/`.gd` de válvulas ya existen en `props/pipe/`

## 6. Verificación

1. Una sala con una `PipeValve` + `GasArea3D` (niebla). Al girar la válvula, la niebla se disipa.
2. La pluma `CryoVent_D` emite cian y se apaga al cerrar la válvula (usa `set_active`).
3. Sin timer: cerrar la válvula es seguro y relajado. El jugador respira.
4. Comportamiento determinista (snapshot/restore del estado de la válvula y la niebla).
