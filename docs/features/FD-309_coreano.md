# FD-309: Coreano (ko) — y cierre de FD-308 (pt_BR)

**Status:** Implemented
**Priority:** P1
**Effort:** Small
**Created:** 2026-09-19
**Completed:** 2026-09-19
**Parent:** FD-303 (i18n UI: extractor + inglés) · FD-308 (pt_BR, diseño)
**Relacionadas:** desparquea la fila "i18n coreano (`ko`)" del parking lot de
`FEATURE_INDEX.md`, cuyo único bloqueador era la fuente.

## Problem

El coreano estaba parkeado por un bloqueador de fuente: ninguna de las 8
tipografías del proyecto tiene un solo glifo Hangul (0 de 11 172 silabarios), así
que todo el UI saldría como tofu. La nota del parking lot asumía además que la
solución costaba ~16 MB (Noto Sans KR) y rompía la estética pixel del juego.

Las dos premisas se cayeron:

1. **La fuente existe y es pixel.** `DungGeunMo` (둥근모꼴, Kil Hyung-jin) cubre
   los 11 172 silabarios Hangul **y** Latin-1 completo, es un dot-font de la
   misma familia estética que Ac437/Silkscreen, pesa 7,3 MB y es **dominio
   público** (nameID 0 = "Public Domain").
2. **Godot 3 sí tiene fallback de fuente.** FD-308 §5 afirma que no
   (`"Godot 3 no tiene fallback nativo por DynamicFont"`). Es incorrecto:
   `DynamicFont` expone `fallback/N` / `add_fallback()` desde 3.0, y
   `DynamicFontAtSize::_find_char_with_font()` recorre los fallbacks cuando el
   glifo no está en la fuente principal. No hace falta fusionar TTFs con
   `fontTools.merge` ni dibujar glifos a mano.

Con eso, el coreano baja de "mini-proyecto de arte tipográfico" a un fallback
declarado en los 17 `DynamicFont` del proyecto.

## Solution

### §1. Extractor no destructivo (bloqueador heredado de FD-308 §1)

`tools/i18n_extract.py` guardaba con header fijo `["keys","es","en"]` y tres
columnas. Cualquier columna de idioma agregada a mano desaparecía **sin aviso**
en la primera re-extracción. Ahora es agnóstico al número de columnas:

- `load_existing_csv()` devuelve `(header, {key -> row completa})`.
- `save_csv()` preserva el header y toda columna más allá de `keys`/`es`.
- Un CSV de 3 columnas sale **byte por byte idéntico** al de antes (regresión de
  FD-303 cubierta por `test_three_column_output_unchanged`).

### §2. La columna y el código de locale

- Header del CSV: `keys,es,en,ko`. `ko` sin país: `OS.get_locale()` en un sistema
  coreano devuelve `ko_KR` y `begins_with("ko")` alcanza.
- 301 filas traducidas (las 280 de FD-303, más 9 claves sin traducir que el
  extractor encontró en `main`, más 12 de la bahía de criocápsulas de FD-304/307).
- `locale/ui_strings.ko.translation` la genera el importer CSV de Godot.

Reglas usadas:

- Nombres propios diegéticos sin traducir: `Odisea`, `CARGOL`, `ODISEA OS`,
  `OdiseaOS`, `GLOO`, `EMP`, `EL ARCA SILENCIOSA`.
- Cadenas de debug/dev (`debug_depth`, `cubemap camera`, `samples`, …) se dejan
  en inglés: son herramientas, no UI de jugador.
- Placeholders (`%d`, `%s`, `%.1f`, `%02d`) preservados y **verificados por
  script**: el conteo por fila coincide entre la clave y la traducción.

### §3. La fuente: un fallback, no 17 fuentes nuevas

`assets/fonts/DungGeunMo.ttf` entra como `fallback/0` de **todos** los
`DynamicFont` del proyecto (17 recursos en 13 archivos). Lo aplica
`tools/add_font_fallback.py`, que es idempotente y tiene `--check` para CI.

Efecto lateral gratis: ese mismo fallback cubre los **13 caracteres que FD-308
§5 identificó como faltantes** en `Ac437_OlivettiThin_8x16.ttf`
(`À Á Â Ã È Ê Í Ó Ô Õ Ú ã õ`). El bloqueador 1 de FD-308 queda resuelto sin
tocar Ac437 ni cambiar el look del texto chico.

### §4. Cableado

1. `SettingsManager.resolve_effective_language()` — `auto` en un sistema `ko`
   resuelve a `ko` (antes caía a inglés). La rama se generalizó: recorre
   `UI_LOCALES` en vez de tener `en` cableado.
2. `SettingsManager.apply_locale_settings()` — carga una `.translation` por
   locale de `UI_LOCALES = ["en", "ko"]`. El `es` se sigue fabricando por
   identidad (la clave **es** el texto en español); se movió fuera del loop para
   que no dependa de cuál locale cargó primero.
3. `OptionsMenu` — ítem `한국어` en índice 3, en `_setup_options()`,
   `_load_ui_values()` y `_on_language_selected()`.
4. `project.godot` §`[locale]` — `ui_strings.ko.translation` sumada a
   `translations`.

### §5. Determinismo

El idioma es configuración local (`SettingsManager`) y no viaja por
`InputDataV2`. **El replay no cambia.**

## Considered Options

- **Fallback de fuente (elegida).** Una declaración por `DynamicFont`, sin tocar
  las fuentes existentes ni su look.
- **Fusionar TTFs con `fontTools.merge`** (lo que recomendaba FD-308 §5a).
  Descartada: el fallback nativo hace lo mismo sin un paso de build, sin un
  artefacto generado en el repo y sin duplicar 7 MB por cada fuente fusionada.
- **Subsetear DungGeunMo a los glifos del CSV.** Descartada por ahora: los
  diálogos dinámicos de la IA Odisea no pasan por el CSV, así que un subset se
  rompería justo ahí. 7,3 MB completos es el precio de no tener ese agujero.
- **Fuente distinta solo para `ko`, cambiada en runtime.** Descartada: hay que
  mantener dos temas en paralelo y el fallback resuelve lo mismo.

### §6. Portugués de Brasil, en el mismo viaje

Una vez hecho §1 (extractor N-columnas) y §3 (el fallback cubre los 13 acentos),
lo único que le faltaba a FD-308 era el texto. Entra en este PR: columna `pt_BR`
de 301 filas y el mismo cableado. FD-308 queda **Implemented**.

Reglas pt-BR: "tela" no "ecrã", "arquivo" no "ficheiro", `você` como tratamiento,
"aparelho" por "dispositivo". `pt_BR` (no `pt`) para que coincida con
`OS.get_locale()`; un sistema `pt_PT` también cae acá, que es mejor que caer a
inglés.

### §7. El "es" deja de fabricarse (Open Question 3 de FD-308, resuelta)

Con `compress=true` el importer produce `PHashTranslation`, que **no** expone
`get_message_list()`. La fabricación del `es` en runtime (copiar cada clave sobre
sí misma) dejaba de funcionar. Tampoco hace falta: el CSV tiene columna `es` real
y el importer genera `ui_strings.es.translation` como cualquier otra. Ahora
`UI_LOCALES = ["es", "en", "ko", "pt_BR"]` y `apply_locale_settings()` es un loop
de cuatro líneas.

Efecto colateral detectado al regenerar: las `.translation` de `es`/`en` que
estaban en `main` **no correspondían al CSV** — tenían espacios finales
(`"REACTOR: "`, `"Global Position: "`) que el CSV ya no trae. Estaban desfasadas
desde FD-303. Quedan sincronizadas.

## Fuera de scope
- **Voces / locución en coreano.** Solo texto.
- **Diálogos dinámicos de la IA Odisea**, que no están en el CSV (mismo agujero
  que ya documentó FD-303).
- **Saltos de línea y ancho de texto coreano.** El coreano parte por sílaba, no
  por palabra; si algún panel angosto se desborda, es ajuste de UI, no de i18n.

## Files Modified

- `tools/i18n_extract.py` — N-columnas (§1).
- `tools/test_i18n_extract.py` — preservación de columna + regresión de 3 columnas.
- `tools/add_font_fallback.py` — **nuevo**, parcheador idempotente de `fallback/0`.
- `locale/ui_strings.csv` — columnas `ko` y `pt_BR` + 9 claves nuevas con `en`.
- `locale/ui_strings.{es,en,ko,pt_BR}.translation`, `locale/ui_strings.csv.import`.
- `tools/i18n_build_translations.gd` — **nuevo**, genera las `.translation` sin
  abrir el editor (abrirlo dispara un reimport completo de texturas: minutos y un
  diff de `.import/` ajeno al cambio).
- `assets/fonts/DungGeunMo.ttf` — **nuevo** (7,3 MB, dominio público).
- 13 archivos con `DynamicFont` (`TinyFont.tres`, `assets/themes/retro_scifi.tres`,
  `assets/fonts/*.tres`, `RadialSelectorV2.tscn`, `AreaInfoScreen.tscn`,
  `MobileUI.tscn`, `FirstRunConsent.tscn`, `HudModeOverlay.tscn`, `SignageBold.tres`).
- `core_v2/autoloads/SettingsManager.gd`, `core_v2/ui/OptionsMenu.gd`, `project.godot`.
- `core_v2/tests/test_i18n.gd` — `test_korean_translation`, `test_korean_font_has_hangul`.
- `docs/features/FEATURE_INDEX.md` — alta de FD-309, baja de la fila del parking lot.

## Verification

1. **Extractor no destructivo.** `python3 tools/i18n_extract.py` sobre el CSV de
   4 columnas no altera `ko`; sobre uno de 3, el output es idéntico al de FD-303.
   Cubierto por `tools/test_i18n_extract.py` (6 tests).
2. **Cobertura de glifos.** `python3 tools/check_glyph_coverage.py --ko` reporta
   los 11 172 silabarios presentes en DungGeunMo.
3. **Fallback en todas las fuentes.** `python3 tools/add_font_fallback.py --check`
   sale con 0 pendientes.
4. **Traducción viva y fuente.** `core_v2/tests/test_i18n.gd` — 7 tests, incluidos
   `test_korean_translation`, `test_portuguese_translation` y
   `test_korean_font_has_hangul` (que también verifica `ã`/`õ`).
5. **Placeholders.** Verificado por script al generar la columna: el multiset de
   especificadores `%…` coincide, **en orden**, entre clave y traducción en las
   301 filas (el orden importa: `%s · %d ALERTA` se formatea con un array).
6. **Cobertura.** Ninguna de las 301 filas queda vacía en ninguna columna.

## Deuda que este FD deja anotada (no resuelta)

- Hay claves en español con **voseo** (`Probá de nuevo`, `Activalo si…`), contra
  la regla de español neutro. Cambiarlas obliga a tocar el código fuente que las
  emite (la clave **es** el texto), así que va aparte.
- `core_v2/ui/retro/DebugOverlay.tscn` arma su `DynamicFont` en runtime desde
  `pixel_font_data`; el parcheador no lo alcanza. Muestra el log crudo del motor,
  que no se traduce, así que no afecta al coreano.


## Seguimiento (2026-09-19): la bahía de criocápsulas

Al rebasar sobre FD-304/307 aparecieron strings nuevos, y la mitad **no se podía
traducir tal como estaban**: se formateaban primero y se asignaban después, así
que el auto-`tr()` del `Label` nunca podía coincidir con la clave.

- `CryoPodsWidget.gd` — se traduce el **formato**, no el resultado:
  `tr("%s · %d ALERTA") % [...]` en vez de `"%s · %d ALERTA" % [...]`. Igual para
  `%d/%d OCUP`, `%d CÁPSULAS`, `%s · NOMINAL`, el título y el estado de la cápsula.
- `SuitOSDrawer.gd` — `draw_string()` **no** pasa por el auto-`tr()` de `Control`:
  `tr(tag)` y `tr("RADIAL LLENO")` a mano.
- Claves agregadas: las 10 que vio el extractor más `NOMINAL` y `ALERTA`, que
  llegan por variable (`tr(tag)`) y por eso el extractor no las ve.
- `test_i18n.gd` ahora **restaura el locale en `after_test()`**: era estado global
  del `TranslationServer` y se filtraba a la suite siguiente (rompió
  `test_cryopods_hudable`). Y ese test fija `es` en vez de heredar el idioma
  que quedara puesto.
