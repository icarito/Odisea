# Entrecasco: la corona entre el tubo de terrazas y el casco

Visión de diseño dictada por Sebastián el 2026-11-15. Es intención de producto, no contrato
de implementación; lo construido hasta ahora está en `specs/scaffold-chunk-catalog.md`.

## El lugar

- La nave es un cilindro de ~8 km. La espiral de terrazas forma un tubo interior (radios
  ~220–290 m). El **entrecasco** es la zona exterior de ese tubo hasta el casco: una corona
  alrededor de todo el cilindro. «Bajo la espiral» significa hacia afuera, no un sótano.
- Con gravedad centrífuga el casco es el piso y el envés de las terrazas, el techo.
- Debe leerse como un espacio técnico creíble de la nave (cuadernas, largueros, tuberías,
  tanques, andamios), no como una pista flotando en el vacío.

## Lo que lo hace jugable

- **Secciones con velocidades de rotación distintas.** Cada sección de la corona gira a su
  propio ritmo.
- **Gravedad variable.** Consecuencia de lo anterior (`g = ω²·r`) y del radio: cambia de
  sección a sección y con la altura dentro de una sección.
- **Peligros** propios de cada sección y de los empalmes entre secciones que giran distinto.
- Se recorre en clave Transit-Run: ruta principal a salto limpio, herramientas como atajo.

## Navegación asistida

- La navegación es una **herramienta diegética** del traje, no un modo que se activa solo.
- El autonavegador funciona **solo mientras se mantiene TAB**; al soltar, el control vuelve
  al jugador.
- TAB quedó exclusivo del autonavegador (2026-11-15); el modo HUD se mudó a otra tecla.

## Episodios de prueba

Cada experimento es una escena suelta, fuera de la línea de campaña, que se abre desde
**Experimentos** en el menú principal (lista en `core_v2/levels/Experiments.gd`). Así se
prueba cada idea en la versión publicada sin recorrer la campaña.

## Sin decidir

- Cuántas secciones, cuánto mide cada una y cómo se empalman dos que giran distinto.
- Qué peligros concretos lleva cada sección.
- Cómo entra el entrecasco en la línea principal de campaña.
