# FD-291: Box3D también en el APK de Android
**Status:** In Progress **Priority:** High **Effort:** Medium **Created:** 2026-09-09 **Reusa:** godot-box3d-3 v0.2.0 (`android_source.zip`), Godot Custom Build (`android/build`), `export_all.yml` **Hermano:** FD-290 (optimizaciones del backend), PR #324 (arranque de la migración)

> **Notas de Odiseo:**
> 1. El síntoma: los APK de Android salían con **Bullet** aunque `export_all.yml` activara Box3D en las otras 6 plataformas. Nada lo decía en voz alta: el APK simplemente traía el motor stock.
> 2. La causa era doble y están las dos arregladas en este PR: el motor que viaja dentro del APK vive en los **AARs commiteados** (`android/build/libs/*.aar`, plantilla stock `3.6.2.stable` = Bullet), y el workflow **nunca escribía** `physics/3d/physics_engine="Box3D"` para Android (`BOX3D_ACTIVE` solo se seteaba al descargar slots de template, y Android no descargaba ninguno).

## Problem

Godot 3 "Custom Build" en Android no usa un template exportable: el APK sale del árbol Gradle commiteado en `android/build`, y el motor que corre dentro del APK vive empaquetado en `android/build/libs/{debug,release}/godot-lib.*.aar` (clases Java + `jni/<abi>/libgodot_android.so` para las 4 ABIs). Esos AARs fueron generados desde el `android_source.zip` **stock de 3.6.2** — es decir, sin el módulo Box3D. Además, el paso "Select the Box3D physics backend" de `export_all.yml` solo corre cuando `BOX3D_ACTIVE=1`, que nunca se seteaba para Android, así que ni el setting llegaba al pck.

Resultado: APK con Bullet sin importar la configuración de las otras plataformas.

## Solution

Tres piezas:

### 1. AARs Box3D (el motor dentro del APK)

El release **v0.2.0** de `icarito/godot-box3d-3` publica `android_source.zip` (plantilla Gradle 3.6.4.rc con el módulo). Regeneramos el árbol:

* `libs/{debug,release}/godot-lib.*.aar` → los de v0.2.0 (verificado: el `.so` lleva `Box3DPhysicsServer` y `physics/3d/box3d_substeps` dentro).
* `config.gradle` → el de la plantilla 3.6.4 (compileSdk/targetSdk 36, buildTools 36.1.0, Kotlin 2.1.21, NDK 29.0.14206865).
* `AndroidManifest.xml` y `GodotApp.java` → base 3.6.4 **re-aplicando** las customizaciones de Odisea: permiso `REQUEST_INSTALL_PACKAGES`, plugins `OdiseaDeepLink`/`OdiseaUpdater`, `OdiseaUpdateFileProvider`, deep link `odisea://replay` y el stash de intents de `GodotApp`.
* Se preservan intactos: splash e iconos de Odisea, `src/com/godot/game/Odisea*.java`, `res/xml/odisea_update_paths.xml`, `godot_project_name_string.xml` (se regeneran en cada export) y `.gdignore`.
* `android/.build_version` → `3.6.4.rc`: el export plugin compara ese archivo contra `VERSION_FULL_CONFIG` del binario que exporta (`export_plugin.cpp:2956`) y aborta si no coincide.

### 2. Exportar con el binario Box3D, no con el 3.6.2 del contenedor

El job Android corría dentro de `barichello/godot-ci:3.6.2` usando su `godot` stock. Por la validación de `.build_version`, eso fuerza `template == exportador`, así que el paso nuevo **"Install Godot (Android, Box3D)"** descarga `godot.box3d.linux.x86_64.headless` del release v0.2.0 y lo usa como exportador. Efecto colateral positivo: el import y el export de Android ahora corren con el mismo motor que ejecutará el juego (las otras plataformas siguen con el exportador stock 3.6.2, que solo empaqueta). La clave de cache de `.import` de Android cambia en consecuencia (re-import único).

### 3. El setting del backend, ahora sí, para Android

* Paso nuevo **"Select the Box3D backend for Android"**: setea `BOX3D_ACTIVE=1` (los AARs ya están commiteados; no hay template que descargar).
* El paso existente "Select the Box3D physics backend" (`if: env.BOX3D_ACTIVE == '1'`) escribe `3d/physics_engine="Box3D"` en `project.godot` antes del export — mismo mecanismo que ya usan las otras plataformas.
* El paso de SDK del contenedor instala lo que la nueva `config.gradle` pide: `ndk;29.0.14206865`, `build-tools;36.1.0`, `platforms;android-36`.

### Considered Options

- **Option A**: Solo cambiar los AARs y dejar el exportador 3.6.2. — La validación de `.build_version` del exportador 3.6.2 (`3.6.2.stable`) abortaría con el árbol regenerado; mantener el árbol viejo con AARs nuevos mezcla Java/NDK de 3.6.2 con motor 3.6.4.
- **Option B**: Regenerar todo el árbol desde el `android_source.zip` v0.2.0. — Pros: motor y glue consistentes 3.6.4, mismo arreglo que instalaría el template desde el editor. Cons: hay que re-aplicar las customizaciones Odisea a mano (hecho, y queda documentado para la próxima regeneración).
- **Selected**: **B**, con exportador Box3D (fuerza la alineación de versiones en vez de pelearla) y customizaciones re-aplicadas en sus posiciones exactas.

## Files to Modify

- `android/.build_version` (modify — `3.6.4.rc`)
- `android/build/AndroidManifest.xml`, `android/build/GodotApp.java`... (modify — base 3.6.4 + customizaciones)
- `android/build/config.gradle` (modify — SDK/Kotlin/NDK de la plantilla 3.6.4)
- `android/build/libs/{debug,release}/godot-lib.*.aar` (modify — motor Box3D v0.2.0)
- `.github/workflows/export_all.yml` (modify — exportador Box3D para Android, `BOX3D_ACTIVE`, SDK components, cache key)

## Verification

1. CI `export_all.yml`: job Android en verde y el artifact `Odisea-Tech-Demo-Android` generado con el backend Box3D.
2. Abrir el APK resultante: `unzip -p Odisea.apk lib/arm64-v8a/libgodot_android.so | strings | grep -i box3d` debe dar positivo, y `grep 3d/physics_engine` sobre el pck desempaquetado (o el log de arranque del juego) debe leer `Box3D`.
3. En un dispositivo: el juego responde a la física igual que en desktop (los replays `.oys` de locomoción son la referencia; drift < 0.01 no aplica entre plataformas — Box3D solo garantiza determinismo cross-platform en 64-bit, y Android ARM64 lo es).
4. Los deep links (`odisea://replay`) y el updater siguen funcionando en el APK nuevo (las customizaciones sobrevivieron al merge).
