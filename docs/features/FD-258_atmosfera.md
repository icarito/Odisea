# FD-258: Sistema Atmósfera (Presión)

**Status:** Design
**Priority:** High
**Effort:** Small
**Created:** 2026-08-15
**Parent:** FD-255 (Maestro)
**Assets a reutilizar:** `systems/AirlockPool.gd`, `props/doors/AirlockChamber.tscn`, `IrisDoorV2.tscn`, `VerticalDoor.tscn`

## 1. Función y lugar físico

La atmósfera es la presión y el aire del sector. Vive en las **esclusas** y compuertas entre
domos. Color **blanco/rojo**. Es el sistema que da los "aviso" de peligro que empujan la ruta
y telegrafían amenaza (la explosión ambiental que pedía Sebastián).

## 2. Lenguaje visual

- Blanco/rojo, sellos y manómetros (medidores de presión) en puertas y esclusas.
- Señal de sistema sano: manómetro en zona estable, sin parpadeo.

## 3. Fallo y aviso

- **Fallo:** sobrepresión → **explosión ambiental**. No mata de golpe, pero mueve: rompe
  pasarelas, abre pasajes, cierra el camino viejo, empuja al jugador. Es el "director de
  escena" que orienta.
- **Aviso (patrón legible, siempre en este orden):**
  1. Parpadeo (manómetro/luz roja)
  2. Chispa (arco eléctrico en el sello)
  3. Boom (explosión ambiental)

El jugador aprende: *parpadeo → chispa → boom*. La anticipación nace sin texto.

## 4. Liberación (mini-game de restaurar)

**Purgar/igualar presión.** Mini-game de "sintonía": un dial de consola que el jugador gira
hasta que la aguja entra en la zona verde (presión estable). Reutiliza `InteractableBaseV2`
con una animación de rotación (mismo patrón que `PipeValve`). Sin timer agresivo, sin enemigo:
es el respiro. Feedback sensorial = catarsis (aguja alineada → tono sube → compuerta sella).

## 5. Integración y archivos

- **Esclusas:** `AirlockChamber.tscn` + `AirlockPool.gd` ya gestionan transiciones entre domos.
  El sistema de presión se apoya en ellas: una esclusa con sobrepresión no abre hasta purgar.
- **Puertas:** `IrisDoorV2.tscn` / `VerticalDoor.tscn` como compuertas que responden al estado
  de presión.
- **Explosión ambiental:** reusar `FireEmitter`/partículas + una fuerza puntual (push) al
  cuerpo del jugador. La explosión es lógica (un trigger con radio) + visual cabalgando encima,
  siguiendo el patrón de `FireSystem`/`IceLevel` (la lógica es un estado, el visual decora).

**Archivos:**
- `core_v2/systems/atmosphere/` (nuevo: estado de presión + trigger de explosión + dial)
- Reusar `AirlockChamber.tscn`, `IrisDoorV2.tscn`, `VerticalDoor.tscn`

## 6. Verificación

1. Una esclusa con sobrepresión: no abre hasta purgar. El dial la desbloquea.
2. La secuencia parpadeo → chispa → boom se ve y anticipa la explosión.
3. La explosión mueve al jugador y/o modifica la ruta, sin matarlo de un golpe.
4. El dial de purga es relajado (sin timer) y determinista.
