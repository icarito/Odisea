# FD-214: Runbin HTML5 — Reproducir hotzones .bin desde URL en build web

**Status:** Open
**Priority:** High
**Effort:** Medium
**Created:** 2026-06-15
**Completed:** -

## Problem

Actualmente las hotzones .bin (capturas de bajo FPS con HZN2 format) solo pueden reproducirse localmente con `runbin.sh`. En el dashboard web ya se pueden listar y descargar, pero para depurar una hotzone el desarrollador debe descargarla manualmente y arrastrarla a Godot. No hay forma de hacer clic en una hotzone del dashboard y verla reproducirse directamente en el build HTML5 de Odisea.

## Solution

Permitir que `odisea_shell.html` acepte `?runbin=URL` como query param: si está presente, el shell descarga el .bin y lo pasa al Engine para que arranque directo en HotzonePlayer con ese bin. Y que el dashboard tenga un botón "▶ Reproducir en Netlify" por cada hotzone que genere el link.

### Considered Options

- **Option A — HotzonePlayer con HTTPRequest interno (GDScript)**:
   El shell pasa la URL como argumento cmdline al Engine. HotzonePlayer.gd detecta el argumento y hace HTTPRequest al bin remoto.
   Pros: mínimo cambio en shell. Cons: CORS — el bin viene del bridge (odisea.educa.juegos:5003) y el build corre en netlify.app, requiere cabeceras Access-Control-Allow-Origin. Además Godot HTML5 puede tener issues con HTTPRequest + binarios grandes.

- **Option B — Shell fetch + engine.loadFiles()**:
   El shell detecta `?runbin=`, fetch() al bin como ArrayBuffer, y lo pasa al engine vía `engine.loadFiles()` como VirtualFileSystem en `user://hotzones/`.
   Pros: sin CORS (el fetch lo hace el shell, cualquier origen ok). Godot lo ve como archivo local. El engine ya está funcionando con el VirtualFS de Emscripten.
   Contras: `engine.loadFiles()` carga archivos en el VFS del engine ANTES de que arranque — si ya arrancó no funciona. Hay que llamarlo antes de `engine.startGame()`.

- **Option C — Shell fetch + IDBFS + parámetro cmdline**:
   Similar a B pero guardando en IndexedDB via Emscripten's IDBFS mount ANTES de iniciar el engine. HotzonePlayer arranca y lee desde ahí.
   Contras: IDBFS requiere que el engine ya haya iniciado y montado el filesystem — catch-22.

- **Selected: Option B** (con variante — el shell descarga el bin, lo inyecta al VFS como recurso, y arranca el engine apuntando a HotzonePlayer.tscn). Es la ruta más limpia: el shell es quien fetcha (sin CORS, sin auth issues si usamos tokens temporales en URL), y el engine solo ve un archivo local.

### Decisión de Auth

El endpoint `/hotzones/:id/download` del bridge requiere Bearer token (el del dashboard). El shell en Netlify no tiene ese token. Soluciones posibles:

1. **Token temporal en URL**: El dashboard, al clickear "Reproducir", llama a un nuevo endpoint del bridge `GET /hotzones/:id/gentoken` que devuelve una URL firmada con token efímero (ej: 5 min de validez). El link generado es:
   `https://odisea.netlify.app/?runbin=https://odisea.educa.juegos:5003/hotzones/:id/download?token=XXXX`

2. **Proxy público con expiración**: El bridge copia el bin a un bucket público (ej: R2/S3 con URL firmada) y devuelve esa URL. Más overhead operativo.

**Seleccionado:** Solución 1 — un endpoint nuevo en el bridge `GET /hotzones/:id/dl-link` que devuelve `{"url": "..."}` con un token JWT de un solo uso o temporal.

## Cambios necesarios

### Bridge Central (odisea_central.py)

Nuevo endpoint:
```
GET /hotzones/<id>/dl-link
Auth: Bearer token (admin/dashboard)
Response: { "url": "https://odisea.educa.juegos:5003/hotzones/<id>/download?token=<jwt>" }
```

El token JWT:
- TTL: 5 minutos
- Claims: `{ "hotzone_id": "<id>", "action": "download", "exp": <unix> }`
- Firmado con secret compartido (la misma variable `ODISEA_BRIDGE_TOKEN` o una nueva `RUNBIN_TOKEN_SECRET`)

El endpoint `/hotzones/<id>/download` debe aceptar `?token=JWT` como alternativa al Bearer header. Verificar JWT, si es válido servir el bin. El JWT incluye el hotzone_id para evitar reuso cross-hotzone.

### odisea_shell.html

1. Al inicio, parsear `URLSearchParams` para detectar `runbin`.
2. Si `runbin` presente:
   - Mostrar step en loading: "Descargando captura de rendimiento..."
   - fetch(runbinURL) → await response.arrayBuffer()
   - Mostrar "Cargando captura en el motor..."
   - Configurar engine con `$GODOT_CONFIG` pero modificando `fileSizes.preload` y `args` para que arranque en HotzonePlayer.tscn
   - Usar mecanismo de Godot HTML5 para pasar el bin como archivo preload (ver Godot 3 export docs para `engine.loadFiles()` o alternativa)
3. Si no hay `runbin`, comportamiento normal (Odisea game actual).

**⚠️ NOTA:** Godot 3 HTML5 permite `engine.loadFiles(files: string[])` que copia archivos al VirtualFS antes de `startGame`. Pero esto es para archivos que el juego lee desde `res://`. Para `user://` necesitamos IDBFS. Mejor alternativa: arrancar el engine normalmente y que el GDScript de entrada (un script autoload o el propio HotzonePlayer) reciba el bin por query param.

**FLUJO REVISADO (más realista para Godot 3 HTML5):**

a. Shell detecta `?runbin=URL`
b. Shell fetch() del bin como ArrayBuffer
c. Shell inicia engine normalmente (con la escena normal del juego o con HotzonePlayer.tscn como escena inicial)
d. El shell expone el bin en `window.OdiseaShell.pendingRunbin = arrayBuffer` antes de llamar `engine.startGame()`
e. Al llegar Godot a `_ready()` del autoload o del HotzonePlayer, hace `JavaScript.eval("window.OdiseaShell.pendingRunbin")` para obtener el bin, lo escribe a `user://` con File API de Godot, y procede a cargarlo.

Este flujo evita pelear con `loadFiles()` y es más sencillo.

### Dashboard (React)

En el componente de lista de hotzones (HistoryOverview en App.tsx), junto al botón de descargar, agregar botón "▶ Reproducir":

```tsx
<button
  type="button"
  onClick={async () => {
    try {
      const res = await apiFetch(`/hotzones/${hz.id}/dl-link`);
      const { url } = await res.json();
      window.open(`https://odisea.netlify.app/?runbin=${encodeURIComponent(url)}`, '_blank');
    } catch (e) {
      notify.error('No se pudo generar link de reproducción');
    }
  }}
  title="Reproducir en Netlify"
  aria-label="Reproducir hotzone en Netlify"
>
  ▶
</button>
```

Necesita import:
- `apiFetch` desde `./api` (ya importada)
- Comprobar que la URL de Netlify venga de una variable de entorno o config

**Opción más simple (sin endpoint extra):** El dashboard puede generar el link sin llamar al bridge, asumiendo que el shell en Netlify fetcha directamente del bridge. Pero entonces el shell no tiene token. Esto fuerza a usar la solución del token temporal sí o sí, porque es el dashboard quien tiene el token y puede generar el link firmado.

### HotzonePlayer.gd (modificaciones mínimas)

Agregar detección de modo "web runbin":
- En `_ready()`, si `OS.has_feature("web")`, buscar el bin en `JavaScript.eval()` 
   o en `OS.get_cmdline_args()`.
- Si encuentra el bin blob, escribirlo a `user://` con `File` API de Godot, 
   luego `_load_binary(ruta)` como siempre.

Alternativamente: si pasamos `--replay-file` como argumento cmdline al engine, 
`OS.get_cmdline_args()` ya funciona en HTML5 (Godot lo parsea del query string 
`?arg1=val1&arg2=val2`). Podríamos pasar `?replay-file=user://hotzones/remote.bin` 
y que el shell ya haya inyectado el archivo en IDBFS.

### Scripts / CI

- `scripts/ci_export.sh`: sin cambios — el build HTML5 ya genera `odisea_shell.html` con los tokens `$GODOT_CONFIG`, `$GODOT_URL`, `$GODOT_PROJECT_NAME`, `$GODOT_HEAD_INCLUDE`, `$ODISEA_TOTAL_BYTES`. Las modificaciones al shell no afectan el reemplazo de tokens.
- El deploy a Netlify es el mismo.

## Files to Modify

1. `core_v2/telemetry/html/odisea_shell.html` — agregar detección `?runbin=`, fetch, inyección al engine
2. `core_v2/tools/HotzonePlayer.gd` — agregar soporte para recibir bin vía `JavaScript.eval()` en web
3. `odisea_central.py` — nuevo endpoint `GET /hotzones/<id>/dl-link` + modificar `GET /hotzones/<id>/download` para aceptar token query param
4. `dashboard/src/components/HistoryOverview.tsx` / `dashboard/src/App.tsx` — botón "▶ Reproducir en Netlify"
5. `dashboard/src/api.ts` — nueva función `getHotzoneDownloadLink(id)`

## Verification

1. Arrancar dashboard, clickear "▶ Reproducir" en una hotzone → se abre nueva tab con Netlify + `?runbin=URL`
2. La URL del token expira a los 5 min → sin token válido, bridge devuelve 401
3. `odisea_shell.html` con `?runbin=URL` inválida → error visible en loading screen, no crashea
4. `odisea_shell.html` sin `?runbin` → comportamiento normal (juego actual)
5. HotzonePlayer en web reproduce frames correctamente (verificar 3 hotzones distintas)
6. En local, `runbin.sh --file hotzone.bin` sigue funcionando (regresión)
