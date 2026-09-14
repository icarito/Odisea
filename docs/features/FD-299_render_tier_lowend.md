# FD-299: Render Tier de low-end — gate por vendor para handhelds GLES3

**Status:** Planned
**Priority:** High
**Effort:** Medium
**Created:** 2026-09-14
**Completed:** -

## Problem

El Anbernic (Mali-G31, GLES3 vía FRT, ROCKNIX, panel 640x480) corre Odisea con
nuestro fork 3.6.4 + Box3D, pero:

1. **Post-process del Environment roto en silencio** (FD-296/§11.10): los levels
   cuyo `Environment` habilita fog + glow + DOF + tonemap ACES
   (`Environment_DomeIntro.tres`) renderizan blanco/cian con el HUD encima.
   El mismo build sin esas pasadas (InteriorLab) renderiza texturizado.
   Confirmado en device con ANNA (screenshots + `INFO_OBJECTS_IN_FRAME=79`
   con la pantalla en blanco).
2. **Carga pesada sin feedback**: Dome_Intro tarda **86 s** en llegar a
   `first_idle_frame`; durante ese bloqueo el jugador ve blanco/plano y lo
   interpreta como "texturas rotas".
3. **Boot con shaders sync**: async se auto-apaga en Mali ("enabled for
   project, but not supported") → la primera corrida compila todo síncrono a
   2-3 fps. El shader cache persiste, pero la primera experiencia es abismal.
4. **UpdateManager compite en gameplay**: descargó el nightly (143 MB) con el
   juego corriendo (spikes de 666 ms en el log de frames).
5. GLES2 queda **descartado** como alternativa (falla distinto: texturas mal
   en el menú — verificado por Sebastián en device).

Los sistemas adaptativos existentes (AdaptiveRenderScale, AdaptiveVisualBudget,
MobileLightBudget) ya amortiguan parte del costo, pero ningún mecanismo decide
**una vez, al boot, qué cosas pesadas no se cargan ni qué pasadas se apagan**
según la capacidad real del GPU. Hoy esa decisión no existe o depende de
`ODISEA_DEVICE=anbernic` (string manual).

## Solution

Un **Render Tier** calculado **una sola vez en `_ready` del boot** (vendor +
nombre de adapter via `VisualServer.get_video_adapter_name()/get_video_adapter_vendor()`),
expuesto como dato de solo lectura. Cero monitores por-frame, cero saltos en
hot code: el tier se **materializa en objetos y en decisiones de carga**.

### Tiers

| Tier | Criterio inicial (a calibrar por device) | Dispositivos de referencia |
|---|---|---|
- `LOW` | GLES3 embebido + adapter "Mali-G3x" (Mali-G31 confirmado), VideoCore, llvmpipe | Anbernic RG35xx/503-class |
| `MID` | Mali-G52/G57, Adreno 6xx (los teléfonos del proyecto educativo) | Redmi Note 9 Pro (Adreno 619) |
| `HIGH` | Desktop GL (x11/windows/macOS), Mali Valhall (G77/G610), Adreno 7xx | Desktop del estudio |

**Regla de inclusión (decisión 2026-09-14): el tier solo gatea adapters
explícitamente verificados en device** (hoy: Mali-G31 vía FRT). Un adapter
desconocido **no** se gatea — nunca dejar caer un device por culpa de otro.
La excepción es la opción manual del jugador ("Forzar modo low end" en
Opciones), que aplica el tier en cualquier hardware por decisión del dueño
del dispositivo.

### Parque ROCKNIX (stats oficiales, ~6509 devices activos, 2026-09)

Clasificación por SoC (el `GL_RENDERER` reporta el modelo Mali tanto en blob
como en panfrost, así que el match por substring funciona en ambos drivers):

| SoC | GPU | Tier propuesto | Devices (est.) | Modelos típicos |
|---|---|---|---|---|
| RK3326 | **Mali-G31 MP2** | **LOW (gateado — verificado)** | 420 | RG351V/M/P, R33S, R36S, XU10, RGB10, ODROID Go2 |
| Allwinner H700 | **Mali-G31 MP2** | **LOW (mismo GPU que RK3326 — gatear)** | 991 | RG35XX Plus/Pro/H/SP, RG28XX, RG34XX, RG40XX, CubeXX |
| RK3566 | Mali-G52 MP2 | MID — **el 55% del parque, a verificar** | 3574 | RG353P/V/M/VS, RG503, RG ARC, RGB30, RGB20SX, RK2023, X55, RG DS |
| RK3576 | Mali-G52 MC3 | MID | 77 | RG Vita Pro |
| S922X | Mali-G52 MP6 | MID | 59 | ODROID Go Ultra |
| RK3399 | Mali-T860 | LOW-MID (viejo, GLES 3.1) | 53 | RG552 |
| SM6115 (SD680) | Adreno 610 | LOW-MID — a verificar | 50 | entry handhelds |
| SM8250 (SD865) | Adreno 650 | MID-HIGH | 661 | Retroid, Odin-class |
| SM8550 (SD8G2) | Adreno 740 | HIGH | 522 | AYN Thor, Odin2 |
| SM8750 / SM8650 | Adreno 830/750 | HIGH | 72 | Odin3, KONKR |
| RK3588 | Mali-G610 MP4 | HIGH | 30 | GameForce Ace |

Lectura operativa: el gate Mali-G31 cubre ~21% del parque hoy (1411 devices);
el **MID de Mali-G52 (RK3566) es el 55%** — habilitarlo requiere verificar en
un device G52 real (el mismo env-strip puede ser suficiente, pero no se gatea
sin prueba, por la regla de arriba).

`HIGH` en desktop aunque el vendor diga Mali (no hay Mali desktop en la flota
hoy; el match por adapter name evita falsos positivos). **UNKNOWN GLES3
embebido → `LOW` conservador** hasta verificar en device (cada habilitación
por-tier se confirma con el protocolo §11.10).

### Qué materializa cada tier

- `LOW` (conservador, lo ya validado hoy):
  - Environment sin post-process: fog/glow/dof/adjustment off + tonemap
    lineal — **ya implementado** en `GLES3VendorGate.gd` (extender de vendor
    "Mali" a tier `LOW`).
  - **Lightmap manual**: el lightmap nativo de GLES3 ata la textura del bake a
    `max_texture_image_units - 4` (unidad 12 en Mali-16), colisionando en
    silencio con las texturas del material → el bake no se dibuja y el nivel
    amanece negro (Dome_Intro: solo el HUD widget visible). `GLES3VendorGate`
    activa el camino manual probado (`IOSLightmapFallback`,
    `ODISEA_MANUAL_LIGHTMAP=1`) en los adapters del tier — verificado el
    mecanismo en device por el equipo (el mismo bug de la era GLES2-iOS).
  - **No instanciar subtrees cosméticos**: decoración, VFX de ambiente y
    overlays de efectos marcados con el grupo `lowend_skip`. El gate los
    libera en `node_added` (corte automático, cero condiciones en gameplay).
    **Nunca** marcar subtrees con colisión, física o gameplay.
  - Overlays del traje (Heat/Frost/Helmet FX) en modo simple u off.
  - `INFO_*`: shadow atlas 2048 + `max_lights_per_object=4` (ya en
    project.godot).
- `MID`: env conservador **solo** para las pasadas que fallen por driver
  (fog/ACES — habilitar tras verificar en un device MID); budgets estándar.
- `HIGH`: todo como hoy.

### Considered Options

- **Option A**: adaptación por-frame con PerformanceMonitor (subir/bajar
  calidad según fps) — **Rechazada**: el proyecto ya la tiene puntual
  (AdaptiveRenderScale) pero como mecanismo *general* añade monitores y
  saltos en hot code, exactamente lo que no se quiere; y en un G31 los
  downtimes por compile stall no se arreglan bajando render scale.
- **Option B**: variantes de escena por dispositivo (`_lowend.tscn`) —
  **Rechazada**: duplica contenido y se desincroniza.
- **Option C (selected)**: tier único calculado en boot + materialización
  declarativa (gate de environments ya hecho, grupos `lowend_skip` para
  cosmética, budgets existentes leen el tier en su `_ready`).

### Rama de trabajo

La rama `performance` (git) es el **workspace de desarrollo y medición** de
los cortes; los commits se prueban en device con el protocolo §11.10
(reboot limpio por hipótesis) y la suite de stress. El merge a `main` se hace
cuando los criterios de verificación cierran — los cortes ya viven detrás del
tier, así que el merge no introduce saltos nuevos.

### ¿Todos los Mali son así de lentos?

No. Mali-G31 (Bifrost 1-2 cores, ~10 GFLOPS) es la entrada de la familia:
G52 ≈ 2x, G57 ≈ 3-4x, Valhall (G77/G610) es otra liga. Además el driver
cambia el resultado: blob ARM vs **panfrost** (Mesa) reportan nombres de
adapter distintos y performance distinta — el FD contempla ambos en la
detección. La conclusión operativa: **el tier se keys por adapter detectado,
no por "es Mali"**; "Mali" a secas solo sirve como gate conservador inicial
(hoy: G31 confirmado, el resto a medir).

### Otros casos a anticipar

- **Adreno 5xx/6xx** (los teléfonos del despliegue educativo): MID — el
  contrato `shader_compilation_mode.Android=0` ya cubre el compile; el tier
  agrega los cortes de carga.
- **VideoCore (Raspberry Pi)**: FRT corre ahí — LOW.
- **llvmpipe / software GL** (emuladores, CI headless): LOW.
- **iOS**: ya cubierto por contratos propios (§11.9) — el gate no toca iOS.
- **Desktop**: HIGH siempre.

## Files to Modify

- `core_v2/autoloads/GLES3VendorGate.gd` (modify): agregar `RenderTier`
  (`LOW/MID/HIGH`), API `get_tier()`, extender el strip de environments al
  tier LOW (ya hace fog/glow/dof/adjustment/tonemap), activar el lightmap
  manual y liberar grupos `lowend_skip` en `node_added`.
- `core_v2/systems/VersionChecker.gd` (modify): el check periódico de updates
  **solo dispara en el menú** — nunca en gameplay (spikes de 666 ms).
- `core_v2/autoloads/SettingsManager.gd` + `core_v2/ui/OptionsMenu.gd/.tscn`
  (modify): opción de usuario **"Forzar modo low end"** (`low_end_forced`)
  que fuerza el tier en cualquier dispositivo, sin depender del adapter.
- `core_v2/update/UpdateManager.gd` (modify): diferir descargas a idle
  (menu/pausa) — hoy descarga 143 MB con el juego corriendo (spikes 666 ms).
- `core_v2/autoloads/IOSLightmapFallback.gd` (sin cambios): el camino manual
  probado se reutiliza tal cual — el gate setea su variable de entorno.
- `core_v2/autoloads/SessionManager.gd` (modify): exponer el tier en el
  heartbeat ANNAV2 (telemetría del parque educativo).
- `portmaster/Odisea.sh` (modify): quitar el gate de glxinfo (falso negativo;
  el tier del motor lo reemplaza).
- `portmaster/README.md` + `.github/workflows/export_all.yml` (modify):
  integrar el binario del fork al zip de PortMaster (pendiente de la sesión
  anterior: tercer argumento de `tools/build_portmaster.sh`).
- `docs/features/FD-299_render_tier_lowend.md`: este documento.

## Verification

1. **Gate visual (Anbernic, GLES3, reboot limpio por §11.10)**: Dome_Intro y
   Dome_Prologue renderizan texturizados, sin velo blanco/cian, con el tier
   `LOW` activo (`[GLES3VendorGate]` en log).
2. **Performance**: menú ≥ 50 fps; dome ≥ 25 fps a 640x480 en build release
   (hoy: 22 fps debug con post-process roto); sin spikes > 100 ms fuera de
   cargas.
3. **Carga**: Dome_Intro `first_idle_frame` < 30 s (hoy 86 s) y pantalla de
   carga visible durante todo el bloqueo.
4. **Cortes cosméticos**: con `lowend_skip` activo, cero diferencias de
   gameplay (colisiones, checkpoints, determinismo — `test_determinism_v2`).
5. **UpdateManager**: cero spikes > 50 ms atribuibles a la descarga con el
   juego en gameplay (medición ANNA/stress).
6. **No regresión desktop**: tier `HIGH` — cero cambios visuales (capturas
   del dome en desktop antes/después).

## Risks

- Falsos positivos/negativos en la detección de adapter (panfrost vs blob);
  mitigación: `UNKNOWN embebido → LOW` + calibración por device real.
- Un subtree marcado `lowend_skip` que resultara tener gameplay: mitigación —
  checklist por nivel y el determinismo test corriendo en CI con el tier LOW
  forzado.
- El fork de FRT puede necesitar parche adicional si alguna pasada del env
  se re-habilita para MID/HIGH: cada habilitación pasa por device real.
