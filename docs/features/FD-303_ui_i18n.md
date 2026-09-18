# FD-303: i18n UI — extracción automatizada de strings + inglés

**Status:** Planned
**Priority:** High
**Effort:** Medium
**Created:** 2026-09-18
**Completed:** -

## Problem

La primera prueba pública (2026-09-17, 8 jugadores en telemetría) incluyó usuarios angloparlantes que no entendieron la interfaz: todo el texto de UI está hardcodeado en español. El repo no tiene ninguna infraestructura de traducción (sin `.csv`/`.po`, sin `TranslationServer`, sin settings de locale en `project.godot`).

Se necesitan: (1) un flujo automatizado de extracción de strings (no inventario a mano), (2) infraestructura mínima de i18n nativa de Godot 3, (3) inglés como primer idioma destino. El español sigue siendo el idioma fuente.

## Solution

Sistema i18n nativo de Godot 3 con CSV y **texto español como clave (retrofit)**. Si falta una clave en la traducción activa, el juego muestra el texto tal cual (español) — fallback seguro sin refactor de escenas.

### Considered Options

- **Option A: pybabel + babel-godot (POT/PO/gettext)**: extractor maduro de la documentación oficial, pero añade dependencias `pip` y tooling gettext al repo/CI, y produce archivos `.pot/.po` con más maquinaria de la necesaria.
- **Option B: script propio en Python 3 stdlib → CSV nativo de Godot**: cero dependencias externas, salida directa al formato que Godot importa (`keys,es,en`), control total de exclusiones, re-ejecutable con semántica merge.
- **Option C: inventario manual**: descartado — cientos de strings, propenso a errores.
- **Selected**: Option B. Gettext puede migrarse después sin tocar código de juego (mismo lookup).
- **Claves**: texto español como clave (retrofit) vs claves estables (`MENU_START`): en Godot 3 los Controls auto-traducen su `text` cuando coincide con una clave, así que el retrofit **no toca ningún .tscn**. Tradeoff aceptado para alfa: si se edita un texto español, su traducción se rompe en silencio (muestra español). Refactor a claves estables → post-Vertical Slice.

### Arquitectura

1. **Extractor** `tools/i18n_extract.py` (Python 3, solo stdlib, un archivo):
   - Escanea `*.gd` (excluye `addons/`):
     - Argumento literal de `tr("...")` y `TranslationServer.tr("...")`.
     - Literales ES asignados a propiedades de UI: `.text = "..."`, `.dialog_text`, `.bbcode_text`, `.placeholder_text`, `.hint_tooltip`, `interaction_text = "..."`.
   - Escanea `*.tscn` (excluye `addons/`): `text = "..."`, `placeholder_text`, `hint_tooltip`, `bbcode_text`, `dialog_text` (regex anclada al formato de serialización de Godot 3: `text = "..."` a inicio de línea).
   - Exclusiones: comentarios `#`, strings con `res://`, `user://`, `/` (rutas), con extensión de archivo (`.png`, `.tscn`, `.gd`, `.wav`, etc.), `class_name`/`extends`, prints/logs/`push_*`/`assert`, strings de 1 carácter.
   - Strings formateados: `"Presiona %s o ESC para cerrar" % x` → clave = literal completo con `%s` preservado (NO la expresión entera).
   - Dedup: literales repetidos → una fila. Salida ordenada alfabéticamente.
   - **Merge sin overwrite**: al re-ejecutar, preserva la columna `en` de filas existentes y filas viejas; añade claves nuevas con `en` vacío; reporta huérfanas (en CSV pero ya no en código) sin borrarlas.
   - Salida: `locale/ui_strings.csv`, header `keys,es,en` (formato CSV de Godot: primera columna literal `keys`, columnas siguientes con código de locale).
   - Reporte stdout: total claves, nuevas, huérfanas. Si no extrae nada → exit 1 (fallar ruidosamente, nunca escribir un CSV vacío).

2. **CSV inicial** `locale/ui_strings.csv`: el propio Jules llena la columna `en` de TODAS las filas en esta sesión. Pautas de traducción: voz sci-fi del juego; términos de lore sin traducir (DDC, Cargol, Elías, Multi-tool); títulos de marca sin traducir (ODISEA, EL ARCA SILENCIOSA se quedan igual); mantener placeholders `%s` y tags BBCode (`[b]...[/b]`) intactos; mayúsculas de menú se conservan ("NUEVA PARTIDA" → "NEW GAME").

3. **Registro** en `project.godot`:
   - `internationalization/locale/fallback="es"`.
   - Registrar en `internationalization/locale/translations` SOLO el `.en.translation` (la columna `es` del CSV es referencia humana; el fallback al texto-clave ya muestra español, no hace falta archivo `.es.translation`).
   - Generar los `.translation` corriendo el import headless del editor con el binario pinneado del proyecto (usar el mismo flujo de import que la CI) y commitear los `.translation` + `.import` generados.

4. **Settings** `core_v2/autoloads/SettingsManager.gd`: nueva variable `ui_language` (`"auto"|"es"|"en"`, default `"auto"`), persistida en `user://settings.cfg` con el patrón existente. Al boot (mismo lugar donde hoy se aplican settings): resolver `auto` → `OS.get_locale()` empieza con `"es"` → `"es"`, si no `"en"`; aplicar `TranslationServer.set_locale(resuelto)`.

5. **Selector** en `core_v2/ui/OptionsMenu.gd`: fila "Idioma" con valores Auto/Español/English. Los endónimos NUNCA se traducen: usar `set_message_translation(false)` + `notification(NOTIFICATION_TRANSLATION_CHANGED)` en ese control y en su popup (patrón de docs para OptionButton). Al cambiar: aplicar `TranslationServer.set_locale()` en caliente + persistir via SettingsManager. Los Controls ya asignados se refrescan solos con la notificación de traducción; el texto asignado por código con `tr()` se re-resuelve al reconstruir la UI (estancamiento menor aceptado en alfa).

6. **Retrofit de código**: envolver con `tr()` los literales UI asignados en código (la lista exacta la da el extractor). Formateo: `footer.text = tr("Presiona %s o ESC para cerrar") % interact_key` (operador `%` de String sobre el resultado de `tr()`).

7. **Tests**:
   - Extractor: tests Python puros sin Godot en `tools/test_i18n_extract.py` (fixtures mini de `.gd`/`.tscn` → CSV esperado; caso f-string; caso merge-sin-overwrite; caso exclusión de rutas).
   - Godot headless (patrón de `tests/` y CI existente): con `set_locale("en")` un Label con texto "NUEVA PARTIDA" muestra "NEW GAME"; con `"es"` muestra español; clave inexistente muestra el texto original sin crash.

## Files to Modify

- `tools/i18n_extract.py` (nuevo) y `tools/test_i18n_extract.py` (nuevo)
- `locale/ui_strings.csv` (nuevo, generado + traducido)
- `locale/ui_strings.en.translation` + `.import` (generados por el import, commiteados)
- `project.godot` (fallback + translations)
- `core_v2/autoloads/SettingsManager.gd` (ui_language)
- `core_v2/ui/OptionsMenu.gd` (selector)
- ~40-60 `.gd` propios (wrapping `tr()`; lista exacta = salida del extractor)

## Verification

1. `python3 tools/i18n_extract.py` regenera `locale/ui_strings.csv` de forma idempotente sin perder traducciones `en` existentes.
2. Import headless genera `.translation` sin errores; el proyecto abre sin warnings de locale.
3. Test headless: `set_locale("en")` → "NUEVA PARTIDA" muestra "NEW GAME"; `set_locale("es")` → español.
4. El selector de Opciones cambia el idioma en caliente y persiste tras reiniciar el juego.
5. QA visual en juego: Menu, HUD de Dome_Intro, prompts de interacción ("Pulsar botón", "Presiona %s o ESC...") y banner de telemetría legibles en inglés.

## Fuera de scope

- Diálogos de la IA Odisea (responde en el idioma del jugador a nivel de prompt, no van por el sistema estático).
- Refactor a claves estables, más idiomas, fuentes no-latinas, remaps de assets por locale.
