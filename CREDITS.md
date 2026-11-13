# Créditos de assets externos

Registro de assets de terceros en Odisea. Regla: solo incluir assets con
licencia que permita redistribución (CC0 / CC-BY / equivalente). Al reemplazar
un placeholder, borrar su entrada de esta lista.

Estados:

- **Confirmado** — origen y licencia verificados con evidencia (URL, LICENSE,
  metadatos o historial de git).
- **Pendiente de decisión** — falta un dato de Sebastián (p. ej. el plan vigente
  de una herramienta) para cerrar la licencia.
- **Pendiente de reemplazo** — no se pudo confirmar un origen redistribuible; el
  asset está en uso y debe reemplazarse por uno CC0/CC-BY o confirmarse.

## Inventario #322 — Dome_Intro (Criogenia)

| Asset | Origen | Autor | Licencia | Estado |
|---|---|---|---|---|
| `assets/textures/Ice/ice_0002_*` (color, ao, normal_directx, normal_opengl, roughness, height) | 3dtextures.me — "Ice 002": https://3dtextures.me/2018/01/04/ice-002/ | Katsukagi (3dtextures.me) | CC0 1.0 — https://3dtextures.me/about/ ("All textures on this site are licensed as CC0") | **Confirmado** (fuente corregida) |
| `assets/sfx/voicebosch-ice-crackling-168594.mp3` | Pixabay: https://pixabay.com/sound-effects/nature-ice-crackling-168594/ | VoiceBosch | Pixabay Content License (uso comercial libre, sin atribución obligatoria) | **Confirmado** (plataforma = Pixabay) |
| `assets/music/Elias... wake.mp3` | Suno, cuenta propia `sebastian302`: https://suno.com/song/493cc355-6b6e-4603-a58e-cbe926232329 | Sebastián Silva (generado con Suno) | Suno: plan Pro/Premier ⇒ derechos comerciales del usuario; plan Free ⇒ solo personal/no comercial | **Origen confirmado / licencia pendiente de decisión** |
| `assets/sfx/explode.wav`, `assets/sfx/explodemini.wav` | probable (sin confirmar): OpenGameArt — "2 High Quality Explosions": https://opengameart.org/content/2-high-quality-explosions | probable: Michel Baradari (apollo-music.de) | probable: CC-BY 3.0 (requiere atribución) | **Pendiente de decisión** |
| `assets/sfx/motor_electrico.mp3` | desconocido — metadatos BWF de export "Pro Tools" (2015-03-09), sin URL ni colección identificable | — | — | **Pendiente de reemplazo** |

### Evidencia y notas por ítem

- **Ice (`ice_0002_*`).** La fila anterior atribuía estas texturas a
  cgbookcase. Esa atribución es incorrecta: cgbookcase no publica ninguna
  textura "Ice" (su catálogo de 632 slugs no tiene "ice") y usa identificadores
  de 2 dígitos (`/textures/rock-16`), no `NNNN`. El patrón de archivos
  `ice_0002_<mapa>_1k.<ext>` y el set de mapas (color, ao, normal directx/
  opengl, roughness, height) coinciden con **3dtextures.me**, que sí tiene
  "Ice 002" y publica todas sus texturas bajo CC0 sin atribución. Confirmado por
  convención de nombres y licencia del sitio; no por checksum (3dtextures.me
  distribuye por carpeta de Google Drive, no por URL directa de archivo).
- **Ice crackling.** Commit que lo agregó: `fadf685a`. Nombre con id `168594`
  resuelto a la página de Pixabay (publicada 2023-09-28). Es un import crítico
  (`ci/critical_imports.json`) y está en uso (`IceLevel.tscn`,
  `Dome_Intro.tscn`, `test_ice_level.gd`).
- **`Elias... wake.mp3`.** Commit `752ef1c2`. El MP3 embebe
  `comment=made with suno; created=2026-02-01T19:55:55Z; id=493cc355-...` y
  `artist=sebastian302`. La licencia de redistribución depende del plan de Suno
  vigente al generar: con Pro/Premier el usuario es dueño y conserva derechos
  comerciales; con el plan Free la obra es solo para uso no comercial. **Falta
  que Sebastián confirme el plan** para cerrarlo.
- **Explosiones.** Commit `25db761b`. Los `.wav` no tienen metadatos de origen.
  El nombre `explodemini.wav` coincide con un asset de Michel Baradari
  documentado como CC-BY 3.0 (OpenGameArt) en otros proyectos abiertos; el set
  "2 High Quality Explosions" de ese autor (`explosions.7z`) es el candidato más
  consistente. No se pudo verificar la descarga exacta: **no se declara
  confirmado**. Están en uso (`Dome_Intro.tscn`).
- **`motor_electrico.mp3`.** Commit `fc457334`. Metadatos BWF de export
  "Pro Tools" (`originator_reference`, `date=2015-03-09`), sin URL ni librería
  identificable; compatible con una librería comercial. Está en uso
  (`Dome_Intro.tscn`) y es import crítico. Sin origen redistribuible confirmable.

### Pendientes de decisión (Sebastián)

1. **Plan de Suno** al generar `Elias... wake.mp3` (2026-02-01). Si es Free, el
   track no es redistribuible y hay que reemplazarlo por música CC0/CC-BY.
2. **Origen de `explode.wav` / `explodemini.wav`.** Si se confirma Michel
   Baradari / OpenGameArt / CC-BY 3.0, agregar la atribución (CC-BY la exige) o
   reemplazar por CC0.
3. **`motor_electrico.mp3`**: reemplazar por un loop de motor CC0 (candidato:
   OpenGameArt "Motor Sound Effect", CC0, https://opengameart.org/content/motor-sound-effect)
   y actualizar su `.import`; es import crítico.

## Otros assets de música (Suno)

Todos los `.mp3` de `assets/music/` (`Shadow Code`, `Tin Cosmos`, `act0/*`,
`Mechanical Heartbeat`, y los de `_unused/`) embeben también
`comment=made with suno` con `artist=sebastian302`. Aplican las mismas
condiciones de licencia que `Elias... wake.mp3` según el plan de Suno; los que
estén en uso deben quedar cubiertos por la confirmación del punto 1.

Los meshes `DomeIntro_*` (criopods, pipes, torre, signage) son generados por el
pipeline propio (`tools/*dome_intro*`), no requieren crédito.

## Addons de terceros (todo el proyecto)

Cada addon trae su propio archivo LICENSE (`addons/*/LICENSE*`): Kenney
prototype textures, gdscript_complexity (MIT), PolyHavenImport (GPL-3),
zylann.scatter, gdUnit3, etc. Ya cubiertos — no requiere acción.

## Proceso para assets nuevos (propuesta #322)

Todo PR que agregue un asset redistribuible nuevo bajo `assets/` o
`core_v2/audio/` debería incluir su fila en este archivo en el mismo PR (ítem de
review). Chequeo barato propuesto: un hook `pre-commit` (junto a los
repo-managed de `scripts/install_git_hooks.sh`) que falle si el commit agrega un
archivo bajo esas rutas y no modifica `CREDITS.md`, con una allowlist para
assets generados por el pipeline propio. No implementado todavía: toca hooks/CI
compartidos y queda a decisión del equipo.
