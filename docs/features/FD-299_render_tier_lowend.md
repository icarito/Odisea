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
| `LOW` | GLES3 embebido + adapter "Mali-G3x" (Mali-G31 confirmado), VideoCore, llvmpipe | Anbernic RG35xx/503-class |
| `MID` | Mali-G52/G57, Adreno 6xx (los teléfonos del proyecto educativo) | Redmi Note 9 Pro (Adreno 619) |
| `HIGH` | Desktop GL (x11/windows/macOS), Mali Valhall (G77/G610), Adreno 7xx | Desktop del estudio |

`HIGH` en desktop aunque el vendor diga Mali (no hay Mali desktop en la flota
hoy; el match por adapter name evita falsos positivos). **UNKNOWN GLES3
embebido → `LOW` conservador** hasta verificar en device (cada habilitación
por-tier se confirma con el protocolo §11.10).

### Qué materializa cada tier

- `LOW` (conservador, lo ya validado hoy):
  - Environment sin post-process: fog/glow/dof/adjustment off + tonemap
    lineal — **ya implementado** en `GLES3VendorGate.gd` (extender de vendor
    "Mali" a tier `LOW`).
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
  tier LOW (ya hace fog/glow/dof/adjustment/tonemap), liberar grupos
  `lowend_skip` en `node_added`.
- `core_v2/tests/test_gles3_vendor_gate.gd` (modify): tests de tier + grupos.
- `core_v2/update/UpdateManager.gd` (modify): diferir descargas a idle
  (menu/pausa) — hoy descarga 143 MB con el juego corriendo (spikes 666 ms).
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
