# Handoff para Kilo — Anbernic: 3D a medias y low-end agresivo

Usted va a ejecutar el plan de [`plan.md`](plan.md). Claude y Sebastián planean y revisan; usted hace el
trabajo en el dispositivo y en el código. Deténgase y reporte en el **Checkpoint 1**, en el **Checkpoint 2**,
y cada vez que una hipótesis no dé lo esperado. No improvise fases nuevas: si el plan no alcanza,
proponga el cambio antes de hacerlo.

## Lea primero

1. `KILO.md` y `AGENTS.md`, sobre todo §11.9 (GLES3 en iOS/Android) y §11.10 (GLES3 en Mali vía FRT).
2. `docs/agents/tooling.md` (telemetría, peer, eval).
3. [`plan.md`](plan.md) completo, con la pre-exploración.
4. `docs/features/FD-299_render_tier_lowend.md`. Ojo: su afirmación de que el atlas 2048 y las 4 luces
   "ya están en project.godot" es falsa para FRT (son claves `.Android`).

## Qué ya está verificado (no lo vuelva a investigar)

- El Anbernic corre **nuestro FRT del fork con Box3D** (`odisea.frt.aarch64`, Godot 3.6.4-rc custom), no el runtime de PortMaster.
- El 3D a medias es el GPU abortando el fragment job en cada frame: `DATA_INVALID_FAULT` en `dmesg`,
  ~421 MB de memoria GPU en un equipo de 1 GB, 58 MB libres.
- En FRT aplica la configuración de escritorio de `project.godot` (MSAA 2x, framebuffer HDR, sombras 4096 con PCF13, 32 luces por objeto).
- `override.cfg` junto al `--main-pack` se carga al arrancar (`core/project_settings.cpp:391` del fork). Es
  la palanca principal de las Fases 1 y 2.
- `MobileLightBudget`, `AdaptiveVisualBudget` y `AdaptiveRenderScale` están apagados en FRT (gate por Android/iOS).

## Acceso y herramientas

- **SSH:** `ssh root@angel.local` (llave ya instalada; ROCKNIX, busybox + systemd).
- **Port en el dispositivo:** `/storage/roms/ports/odisea/` (alias `/roms/ports/odisea/`). Log del juego en `log.txt`,
  settings del jugador en `conf/godot/app_userdata/Odisea/settings.cfg`. `override.cfg` y `dev.sh` van en esa carpeta.
- **Captura de pantalla** (sway):
  ```bash
  ssh root@angel.local 'XDG_RUNTIME_DIR=/var/run/0-runtime-dir WAYLAND_DISPLAY=wayland-1 grim /tmp/shot.png'
  scp root@angel.local:/tmp/shot.png /tmp/odisea_probe/<etiqueta>.png
  ```
  La pantalla es 640x480; si alguna imagen supera 2000 px, redimensiónela antes de mirarla.
- **Métricas del GPU:**
  `dmesg | grep -c "GPU fault"` (contar delta), `cat /sys/kernel/debug/mali0/gpu_memory` (páginas por contexto),
  `grep MemAvailable /proc/meminfo`.
- **Telemetría:** el juego manda heartbeat al central. `GET https://odisea.educa.juegos/status` con
  `Authorization: Bearer $ODISEA_BRIDGE_TOKEN` (variable de `src/.env`; nunca la imprima ni la pegue en logs).
  El Anbernic aparece con `host: "Unix"`; mire `player.fps`, `player.perf.{dc,vtx}` y `player.render_diag`.
  El hook `rtk` reescribe `curl` y puede romper el JSON: use `rtk proxy curl`.
- **Control fino:** el build release no acepta `eval` ni `screenshot` desde el central. Para eso, binario
  `godot.box3d.frt.arm64.debug` del release del fork (versión en `.github/box3d_release`) +
  `dev.sh` con `export ANNA_V2_BRIDGE=192.168.18.6:4999` y el peer local (`tools/ensure_peer.sh`).
- **Instalar un build local:** `make portmaster-install` (arma el zip y hace rsync a `angel.local`).
- **Relanzar el juego:** mate `odisea.frt.aarch64` por SSH y pida a Sebastián que lo abra desde ES, o pruebe
  relanzar `Odisea.sh` con el entorno de `/proc/<pid>/environ`. Anote en este archivo lo que funcione.

## Reglas duras

- **Una hipótesis por reinicio limpio del juego.** El estado GL no se cambia en vivo (§11.10).
- No edite el bloque `[rendering]` de `project.godot` para esto: los ajustes de arranque van en
  `portmaster/override.cfg`, y los de runtime detrás del tier LOW de `GLES3VendorGate`.
- No reserialice `.tscn` grandes con scripts (`PackedScene.pack()` borra overrides en instancias anidadas).
  Si Godot está abierto en el editor, puede pisar lo que usted edite: avise a Sebastián.
- Godot local solo con `tools/godot_bin.sh`; nunca un Godot del sistema.
- Tests puntuales de lo que toque; nunca la suite completa en local.
- Español neutro en código, comentarios, UI y commits (sin voseo).
- Rama `fd-299-anbernic-lowend`, commits chicos por fase, sin push a `main`. Si hace falta `gh` con escritura:
  `gh auth switch --user icarito`.
- No active el lightmap manual fuera de Mali, no gatee adapters no verificados, no toque el updater
  (PortMaster lo maneja) y no vuelva a GLES2 (descartado).

## Qué entregar en cada fase

1. Filas nuevas en la tabla **Resultados** de `plan.md`: etiqueta, cambio, escena, faults/60 s, páginas GPU,
   MemAvailable, fps, dc, vtx, cobertura 3D.
2. El diff chico de la fase y su commit.
3. Un párrafo de "qué aprendimos" listo para AGENTS.md §11.10 (causa real del fault y la combinación de settings que lo quita).
4. En los checkpoints: la captura de `grim` y la fila de métricas, y espere el visto bueno.

## Primer paso sugerido

Fase 0: escriba `tools/anbernic_probe.sh`, corra la línea base en menú, Dome_Prologue y Dome_Intro con el
build 602 instalado, y después H1 (`msaa=0`, `use_fxaa=false` en `override.cfg`). Reporte las dos filas antes de seguir.
