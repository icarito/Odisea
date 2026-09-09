# Cache binario de shaders GLES3 en Android (Godot 3.6.2)

## Sintoma

En Android, entrar por primera vez a un nivel pesado (Dome_Intro) bloquea el
main thread ~40 s en el primer frame dibujado: compilacion sincrona de ~90
programas GLES3 en Adreno. Godot 3.6 trae la solucion ("Asynchronous + Cache",
`rendering/gles3/shaders/shader_compilation_mode = 2`): compila en fondo y
guarda los binarios de programas en disco para las corridas siguientes.
Pero el cache nunca se relee: cada corrida vuelve a compilar todo.

## Causa raiz

`DirAccessJAndroid::make_dir_recursive()` (platform/android/dir_access_jandroid.cpp)
devuelve `ERR_ALREADY_EXISTS` cuando el directorio ya existe, mientras que la
implementacion generica `DirAccess::make_dir_recursive()` tolera ese error y
devuelve OK.

`ShaderCacheGLES3::ShaderCacheGLES3()` llama a `make_dir_recursive()` en el
init del rasterizador y se desactiva ante cualquier error:

```
Shader cache: ON
ERROR: Couldn't create shader cache directory. Shader cache disabled.
```

Corrida 1: el directorio `cache/godot/shaders` no existe -> se crea (el handler
Java usa `File.mkdirs()`) -> cache ON -> escribe los binarios.
Corridas 2+: el directorio existe -> `ERR_ALREADY_EXISTS` -> cache OFF -> no se
leen los binarios -> recompilar 40 s en cada arranque de proceso.

## Parche

`dir_access_jandroid_make_dir_recursive_idempotent.patch` (en este directorio):
si el directorio ya existe, devolver `OK` (idempotente, mismo contrato que la
implementacion generica). Se aplica sobre el tag `3.6.2-stable`.

## Pipeline

`build.sh` clona el motor, aplica el parche, compila `release_debug` para
arm64 (el APK debug de este proyecto es arm64-only) y empaqueta el AAR:

```shell
./tools/godot_android_template/build.sh ~/src
```

Instalar el AAR en el template local (y en `android/build/libs/debug/` del
proyecto, que es donde el export custom build lo busca):

```shell
cp ~/src/godot36/platform/android/java/lib/build/outputs/aar/godot-lib.debug.aar \
   android/build/libs/debug/godot-lib.debug.aar
# y dentro de ~/.local/share/godot/templates/3.6.2.stable/android_source.zip
# reemplazar libs/debug/godot-lib.debug.aar
```

El scons de 3.6.2 exige NDK `28.1.13356709` bajo `$ANDROID_SDK_ROOT/ndk/`
(`platform/android/detect.py:34`) y sino intenta instalarlo via sdkmanager.
Si el sdkmanager del sistema falla, crear un overlay:

```shell
mkdir -p ~/src/android-sdk-overlay/ndk
curl -L -o /tmp/ndk.zip https://dl.google.com/android/repository/android-ndk-r28b-linux.zip
unzip /tmp/ndk.zip -d /tmp && mv /tmp/android-ndk-r28b ~/src/android-sdk-overlay/ndk/28.1.13356709
ln -sfn /opt/android-sdk/{platforms,build-tools,cmdline-tools,licenses,tools} ~/src/android-sdk-overlay/
export ANDROID_SDK_ROOT=~/src/android-sdk-overlay
```

## CI (export_all.yml)

El job Android de CI NO re-instala el template: el exportador 3.6 ve que
`android/build/build.gradle` existe (está en el repo) y usa el proyecto tal
cual, consumiendo `android/build/libs/debug/godot-lib.debug.aar` del checkout.
Por eso basta con commitear el AAR parcheado — no hay que cambiar el workflow.

Notas:
- El AAR commiteado trae arm64-v8a + armeabi-v7a (ambos parcheados). El preset
  habilita solo arm64-v8a (`architectures/`), así que el APK sigue arm64-only
  como antes. Si algún día se habilitan x86/x86_64 (emuladores), recompilar el
  AAR con `android_arch=x86` / `x86_64` (ese AAR no los trae).
- `godot-lib.release.aar` sigue siendo el oficial SIN parche: CI exporta solo
  debug (`--export-debug`). Si se llega a exportar release, regenerar el AAR
  release con `build.sh` cambiando `target=release` y
  `:lib:assembleTemplateRelease`, o el release pierde el cache (y con
  `shader_compilation_mode.Android=2` el cache-off lo deja como el build
  actual, sin regresión pero sin beneficio).
- Verificación rápida de que un APK trae el motor parcheado: en logcat el boot
  imprime `Godot Engine v3.6.2.stable.custom_build` y `Shader cache: ON` sin el
  error `Couldn't create shader cache directory`.

## Proyecto

`project.godot`:

- `gles3/shaders/shader_compilation_mode.Android=2` ("Asynchronous + Cache").
- `gles3/shaders/shader_cache_size_mb.mobile=512` (ver "Tamano del cache").

Con el motor parcheado:

- Corrida 1 (cache vacio): compila en fondo; el ubershader de fallback tiene
  errores conocidos en Adreno (`_bind_ubershader !version`), ver §11.9.
- Corridas siguientes: los ubershaders cargan de binario (~ms), sin recompilar.

El modo 0 (sync, sin cache) sigue siendo el contrato para iOS (§11.9).

## Que cachea realmente (y que no)

`ShaderGLES3::VersionKey::is_subject_to_caching()` (drivers/gles3/shader_gles3.h)
es literalmente `version & UBERSHADER_FLAG`: **solo se cachean los ubershaders**,
no los programas especializados. Esos se recompilan de fuente en cada proceso.

Por eso el cache en disco NO elimina el stall entero de entrar por primera vez a
un nivel. Medido en desktop (Iris Xe, cache ya caliente), primera entrada a
Dome_Intro desde el Menu: 3.5 s hasta `first_idle_frame`, de los cuales 3.2 s son
UN solo frame. La segunda entrada al mismo nivel dentro del mismo proceso: 0.64 s.
Ese delta es costo por-proceso (link/validate del binario, subida de texturas y
lightmaps a VRAM) que ningun cache en disco puede adelantar.

La unica palanca que si lo adelanta es el warmup en proceso
(`core_v2/levels/shader_cache/*.tscn` + `ShaderWarmupTrigger`), que corre en el
Menu antes de que el jugador entre.

## Tamano del cache

El cache vive en `OS::get_cache_path()/godot/shaders` (fuera de `res://`, sin
setting para redirigirlo) y se purga por LRU en cada arranque contra
`rendering/gles3/shaders/shader_cache_size_mb`. Defaults del motor: 512 MB
desktop, **128 MB** mobile y web.

Working set real de Odisea, medido contando los archivos con mtime fresca tras
una corrida (`retrieve()` reescribe la mtime en cada acierto, justamente para el
LRU):

| recorrido | programas | tamano |
|---|---|---|
| Boot + Menu + Dome_Intro | 84 | 163 MiB |
| + Dome_Crio | 111 | 216 MiB |

Un nivel entero de mas costo solo 27 programas: hay mucho solapamiento, asi que
el juego completo deberia quedar holgadamente por debajo de los 512 MB de
desktop. Por eso desktop se deja en el default.

Los 128 MB de mobile, en cambio, estan por debajo del working set de UN nivel:
el cache se purgaba entero en cada corrida y volvia a compilar, que es
exactamente el sintoma que el parche del AAR existe para evitar. De ahi
`shader_cache_size_mb.mobile=512`. Subir un tope no reserva disco: el cache solo
crece hasta lo que realmente se usa.

El tamano por programa (1.94 MiB de promedio en Mesa/Intel) es especifico del
driver, asi que en Adreno el numero cambia; 512 se elige porque el *conjunto* de
programas es el mismo. Si alguna vez hay que reajustarlo, esa es la perilla.

Web queda afuera de todo esto: `rasterizer_storage_gles3.cpp` hace
`config.program_binary_supported = false` bajo `JAVASCRIPT_ENABLED`, asi que el
cache nunca se instancia (`Shader cache: OFF (enabled, but not supported)`) por
mas que `shader_compilation_mode.web=2`. No es un bug de Godot: WebGL2 no expone
ninguna API de binarios de programa. Alla el modo 2 solo compra la mitad
asincrona, y lo unico que cachea es el navegador, por origen.
