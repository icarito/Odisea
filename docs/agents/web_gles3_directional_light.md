# Web (WebGL2): la luz direccional descartaba la mitad de los draws

**Sintoma.** En el build HTML5, y solo ahi, muchas superficies salian planas o directamente
no se dibujaban: el traje del piloto, tuberias, tanques de coolant, airlocks, parte del HUD
3D. En nativo (Linux/Windows/Android) las mismas escenas estaban bien. Cambiaba entre
corridas segun donde estuviera la camara, lo que despistaba mucho.

En consola, cientos de veces por ventana de reporte:

```
GL_INVALID_OPERATION: glDrawElements: it is undefined behaviour to use a uniform buffer
that is too small.
WebGL: Buffer for uniform block is smaller than UNIFORM_BLOCK_DATA_SIZE
```

## Causa: bug de Godot 3.6, no del juego

`drivers/gles3/shaders/scene.glsl` termina el bloque `DirectionalLightData` asi:

```glsl
mediump vec4  shadow_split_offsets;   // offset 352..368
mediump float fade_from;              // offset 368..372
mediump vec3  pad;                    // std140 alinea vec3 a 16 -> 384..396, bloque = 400
```

y `drivers/gles3/rasterizer_scene_gles3.h:591` declara el mismo tramo como
`float fade_from; float pad[3];`, pegados en C: **la struct mide 384 bytes**.

Godot ata un buffer de 384 donde el driver calculo 400. El GL de escritorio no valida el
tamano del bloque, por eso en nativo no pasa nada nunca. **WebGL2 si valida y descarta el
draw entero.** Todo objeto dibujado en un pase que ate ese UBO desaparecia o perdia su
material. El bloque de omni/spot (`LightData`, 160 bytes) no tiene el problema.

La rama 3.6 sigue con `float pad[3]`: no hay arreglo publicado rio arriba.

## Solucion: plantilla de exportacion propia

Una linea, en el motor:

```glsl
mediump vec3 pad;   ->   mediump float pad0; mediump float pad1; mediump float pad2;
```

Con tres floats el bloque cierra en 384 y coincide con la struct. `pad` es relleno, no se
lee en ningun lado del shader.

- El parche vive en `tools/godot_web_template/scene_glsl_directional_ubo.patch`.
- `tools/godot_web_template/build.sh` lo reproduce entero: emsdk 3.1.39, Godot en el tag
  `3.6.2-stable`, `scons platform=javascript tools=no target=release threads_enabled=yes`.
  Son ~10 minutos de compilacion en 8 nucleos.
- La plantilla resultante se publica como asset de release y CI la baja en el job de html5;
  el preset "HTML5 Threads" (`variant/export_type=1`) lee **`webassembly_threads_release.zip`**
  (ojo: no el slot `webassembly_release.zip`, pese a lo que decia un comentario del workflow).

Para probar en local:

```bash
cp ~/src/godot36/bin/godot.javascript.opt.threads.zip \
   ~/.local/share/godot/templates/3.6.2.stable/webassembly_threads_release.zip
```

Guardar antes el oficial (`.oficial`) para poder volver.

**Verificado el 2026-09-04**: con la plantilla parcheada, cero errores de "uniform buffer
too small" (antes 254 por ventana, o sea todos), y el traje, el panel y la barra de vida
vuelven a dibujarse con el sol prendido y sin ningun parche del lado del juego.

Quedan en consola errores de `Feedback loop formed between Framebuffer and active Texture`:
son otra cosa, preexistente, de los shaders que leen pantalla.

## Como reproducirlo / verificarlo sin re-exportar

El truco reutilizable es usar el bridge de ANNA V2 como REPL dentro del build web:

1. Exportar **con debug** (`--export-debug`), unico modo en que
   `_can_execute_remote_command` deja pasar `execute_script`.
2. Servir el build con un servidor threaded (`http.server` simple se cuelga con el .pck) y,
   si el build es de hilos, con cabeceras `Cross-Origin-Opener-Policy: same-origin` y
   `Cross-Origin-Embedder-Policy: require-corp`; sin eso el shell redirige a Vercel.
3. Parchear el `index.html` exportado para que no se traiga wasm/pck de GitHub Pages
   (`var isPck = false; var isWasm = false;`), o se mezcla el build local con el publicado.
4. En la pagina, envolver `ANNAV2_WS_Bridge.poll` para inyectar comandos sin peer:

   ```js
   var orig = ANNAV2_WS_Bridge.poll.bind(ANNAV2_WS_Bridge), extra = [];
   window.__anna_eval = function (src) {
     extra.push(JSON.stringify({type: "command", action: "execute_script",
                                args: {script: src}, id: "e" + Date.now()}));
   };
   ANNAV2_WS_Bridge.poll = function () {
     var r = orig() || []; if (extra.length) { r = r.concat(extra); extra = []; } return r;
   };
   ```

   Envolver tambien `ANNAV2_WS_Bridge.send` para leer las respuestas. El script debe ser de
   **una sola linea** (`_validate_remote_script` rechaza saltos de linea).
5. A/B: `__anna_eval("get_tree().get_current_scene().get_node('DirectionalLight').visible = false")`
   y capturar antes/despues. El juego en pausa sigue renderizando, asi que la comparacion
   vale aunque la ventana pierda el foco.

Para medir el UBO directamente, envolver `WebGL2RenderingContext.prototype.bindBufferBase`
y comparar `getActiveUniformBlockParameter(prog, i, UNIFORM_BLOCK_DATA_SIZE)` contra
`getBufferParameter(UNIFORM_BUFFER, BUFFER_SIZE)`. Ojo: hay que releer los bindings del
programa en cada llamada; cachearlos da falsos negativos.

## Lo que NO era (descartado con evidencia)

- **Formato de textura.** Reproducido con un pck sin un solo BPTC (122 DXT + 145 ETC2). El
  arreglo de BPTC en CI (`3a788efe`) es correcto y necesario, pero es otro bug.
- **Compilacion asincrona de shaders.** El motor reporta `Async. shader compilation: OFF`
  en web pase lo que pase. El congelamiento al arrancar es la compilacion sincrona de ~95
  programas; se ataca aparte.
- **Mitigacion por FPS bajo.** Medida en vivo: `_performance_mitigation_active = False`.
- **El shader de dither de props.** Apagado desde el menu de opciones, sin cambio.

## Trampas del banco de pruebas

- El navegador **headless corre por software (SwiftShader) a 1 FPS**: sirve para leer
  consola, no para juzgar como se ve. Las conclusiones visuales van sobre ventana real.
- El juego entra en PAUSA al perder el foco y la camara puede quedar dentro de la
  geometria: comparar siempre el mismo frame, no dos corridas distintas.
- La rama `3.6` de Godot ya va por 3.6.4-rc. Compilar desde la rama da una plantilla de
  otra version que la del editor; usar el tag `3.6.2-stable` para que la unica diferencia
  contra la oficial sea nuestra linea.
