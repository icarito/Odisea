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

`project.godot`: `gles3/shaders/shader_compilation_mode.Android=2`
("Asynchronous + Cache"). Con el motor parcheado:

- Corrida 1 (cache vacio): compila en fondo; el ubershader de fallback tiene
  errores conocidos en Adreno (`_bind_ubershader !version`), ver §11.9.
- Corridas siguientes: los programas cargan de binario (~ms), sin compiles,
  sin bloqueos ni thrash.

El modo 0 (sync, sin cache) sigue siendo el contrato para iOS (§11.9).
