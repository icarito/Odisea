# Oscurecer un nivel y guiarse con la linterna

Cómo dejar un nivel a oscuras para que la linterna de Elías sea la forma de
guiarse, en escritorio y en el handheld. Son **dos implementaciones distintas del
mismo diseño**, porque el tier bajo no puede usar la misma.

## Por qué hacen falta dos

En el handheld los materiales del mundo corren **unshaded** (`FlatFake.shader`,
que activa `ODISEA_UNSHADED=3` desde `Odisea.sh`). No hay light loop: ahí está el
ahorro que hace viable el perfil bajo, y también el motivo de que **una SpotLight
real no ilumine nada**. Bajar `ambient_light_energy` del Environment tampoco
oscurece: los materiales unshaded lo ignoran.

| | escritorio | tier bajo (modo plano) |
|---|---|---|
| oscuridad | `Environment`: ambient + niebla | uniform `world_light` del shader |
| linterna | `SpotLight` real del casco | cono analítico en el fragment |
| glow map | sí (lens dirt) | no: el gate apaga el glow en Mali |

## Escritorio: `DarkLevelLighting`

Nodo suelto en el nivel (ya está en `RingHub_Level`). En `_ready` duplica el
`Environment` —el `.tres` lo comparten otros niveles— y aplica ambient, niebla,
glow y glow map. **Se auto-inhibe en modo plano**, donde no haría nada.

Exports: `ambient_energy` (0.03), `fog_begin`/`fog_end` (3/26), `sun_energy`
(0.02), `glow_intensity` (1.7), `glow_map`, `glow_map_strength` (0.75).

También apaga la sombra **de la propia linterna** (`disable_flashlight_shadow`).
`Pilot_v2.tscn` la enciende, y con la lámpara a ~20 cm del cuerpo el torso entra
en el frustum del spot y proyecta astillas dentro del haz. Godot 3 no deja
excluir un mesh de las sombras de *una* luz (`light_cull_mask` filtra la
iluminación, no el casteo), así que se apaga esa sombra: Elías sigue proyectando
las de las demás luces.

## Tier bajo: `FlatFakeFlashlight.shader`

Copia de `FlatFake` con la linterna calculada analíticamente. Cuesta unas pocas
ALU sobre un fragment que ya se pagaba: sin pases nuevos, sin sombras, sin luces.
Hay variante `DoubleSided` **obligatoria**: rejillas y decks son `CULL_DISABLED` y
son la mayor parte del nivel — sin ella la escena no se oscurece.

`GLES3VendorGate` lo activa junto con el modo plano (`ODISEA_FLASHLIGHT=0` lo
apaga para comparar) y **sincroniza la linterna a 20 Hz**: Godot 3 no tiene
uniforms globales, así que hay que escribir `flashlight_pos`, `flashlight_dir`,
`flashlight_on` y el cono a cada material del caché. Son pocos (uno por color, no
uno por nodo) y aquí la CPU es lo escaso, por eso no va por frame.

El cono **se deriva de la `SpotLight`** (`spot_angle`, `spot_range`), no se fija a
mano: si no, el haz analítico y el `VolumetricCone` —que es geometría y se ve
igual en modo plano— quedan con radios distintos y se nota el borde.

Perillas: `world_light` (0.02 = oscuridad casi total) y `glow_floor` (0.15).

## Para cablearlo en otro nivel

1. Agregar un nodo con `DarkLevelLighting.gd` y asignarle `glow_map`.
2. Nada más: el tier bajo ya está cubierto por el gate.
3. Calibrar `world_light` mirando **en el dispositivo**, no en escritorio.

## Lo que costó aprender

- **El `glow` de `FlatFake` es un bypass del sombreado.** Las barandas del bake se
  marcan con emisión igual que las lámparas, así que quedaban inmunes a la
  oscuridad. Por eso existe `glow_floor`: atenúa el glow con la escena sin
  apagarlo del todo, para que las lámparas sigan siendo la guía visual.
- **El cono no puede colgarse del eje de la cámara.** Da un headlight de primera
  persona; la cámara va en tercera y la linterna apunta con Elías. Va en espacio
  de mundo, con `CAMERA_MATRIX` llevando el fragmento ahí.
- **El glow map sólo multiplica el glow existente.** Sin halos en pantalla no hace
  nada — no es un efecto que se vea "en todos lados". Medido: con `strength 0.85`
  cambia el 12% de los píxeles, todos donde ya había emisión.
- **Un PNG sin importar rompe la escena entera.** Referenciarlo desde el `.tscn`
  sin `.import` deja `RingHub_Level` sin cargar (`Parse Error`). Importar es
  correr el editor **sin** `--quit` y esperar a que aparezca el `.import`; después
  `git add -f` del `.stex` y el `.md5`, o CI los borra.
- **Para probar el nivel hay que usar `tools/launch_game.sh`.** Instanciar la
  escena a mano saltea Boot/SessionManager y el nivel aparece sin HUD ni consola
  de criogenia: parece roto y no lo está.

`FlashlightConeVolumetric.shader` queda entregado pero **sin usar**: en el
dispositivo se leía como una burbuja blanca (es aditivo y satura sobre fondo
negro). Candidato para escritorio con `beam_energy` mucho más bajo.
