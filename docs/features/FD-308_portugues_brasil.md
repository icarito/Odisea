# FD-308: Portugués de Brasil (pt_BR)

**Status:** Implemented
**Priority:** P1
**Effort:** Small
**Created:** 2026-09-19
**Completed:** 2026-09-19 (junto con FD-309)
**Parent:** FD-303 (i18n UI: extractor + inglés) · FD-296 (OdiseaOS)
**Relacionadas:** FD-303 dejó "más idiomas / fuentes no-latinas" fuera de scope. Este FD **cierra el caso latino** de esa deuda.

## Problem

FD-303 (PR #356, en main) dejó el pipeline i18n funcionando con
**dos** idiomas: español (clave) e inglés (traducción). El juego corre en `es`/`en`
y el menú de opciones ofrece exactamente esas dos.

Pedido: **portugués de Brasil** como tercer idioma.

Es viable —el alfabeto es latino— pero al verificar encontré **dos bloqueadores
reales**, y ninguno se descubre leyendo el FD-303:

### Bloqueador 1 (duro, pero preciso): la fuente "tiny" no tiene `ã` ni `õ`

`TinyFont.tres` usa `assets/fonts/Ac437_OlivettiThin_8x16.ttf`. Verificado con
`fc-query` (charset real de fontconfig) y con un parser propio de la tabla `cmap`:

**Faltan exactamente 13 caracteres:**

```
À Á Â Ã È Ê Í Ó Ô Õ Ú  ã õ
```

Es decir: **la fuente se cae justo en los caracteres más portugueses que existen.**
`ã` y `õ` son la firma del portugués — `não`, `são`, `opções`, `ação`, `coração`,
`botão`, `cãibra`. La `ç` sí está (C7/E7), así que el problema es específico.

**Dónde se usa esa fuente** (`TinyFont.tres`):

| Consumidor | Qué muestra |
|------------|-------------|
| `core_v2/components/ui/InteractionMarker.gd` | el prompt de interacción ("ABRIR", "USAR") |
| `core_v2/ui/overlay/PlayerHintOverlay.gd` | pistas al jugador |
| `core_v2/ui/overlay/InfoOverlay.tscn` | overlay de información |
| `core_v2/ui/retro/SubtitlesOverlay.gd` | **subtítulos** |
| `core_v2/props/signage/AreaInfoScreen.tscn` | carteles |

Sin las 13 letras, el portugués muestra **tofu** justo en los overlays y en los
subtítulos. El resto del UI (tema `retro_scifi.tres` → `Workbench`, radial y
signage → `SyneMono`, `DomeIntro` → `Silkscreen`) **sí cubre pt-BR completo**
(7 de las 8 fuentes del proyecto pasan la verificación; ver §5).

Buenas noticias: a diferencia del coreano, acá son **13 glifos en una sola
fuente**, y el rango que falta es un bloque contiguo del Latin-1 (`C0–C3`,
`C8`, `CA`, `CD`, `D2–D5`, `DA`, `E3`, `F5`). Es un parche acotado, no un
proyecto de arte tipográfico nuevo.

### Bloqueador 2 (silencioso): el extractor **borra** columnas extra

`tools/i18n_extract.py` es idempotente para 3 columnas exactas, pero su
guardado está cableado:

```python
def save_csv(csv_file: Path, keys_map: dict):
    ...
    writer.writerow(["keys", "es", "en"])          # header FIJO
    for key in sorted_keys:
        writer.writerow([key, key, keys_map[key]])  # solo 3 columnas
```

Y la lectura solo devuelve `key -> en` (`load_existing_csv`).

**Consecuencia:** el día que alguien agregue una columna `pt_BR` a mano y después
corra el extractor (que es lo que pide FD-303 en su flujo normal, y lo que corre
cualquiera que toque un string), **la columna `pt_BR` desaparece sin aviso y sin
error.** Se pierde la traducción completa y el commit se ve "normal".

Esto hay que arreglarlo **en este FD**, antes de escribir una sola traducción.

### Bloqueador 3 (menor): el idioma no está cableado en 4 lugares

El sistema está cableado a dos idiomas en puntos que no son obvios:

1. `core_v2/autoloads/SettingsManager.gd` — `resolve_effective_language()`:
   ```gdscript
   if sys_locale.begins_with("es"): return "es"
   else: return "en"
   ```
   Un sistema en `pt_BR` con `ui_language = "auto"` **cae a inglés**. El jugador
   brasileño nunca ve portugués salvo que lo elija a mano.
2. `core_v2/autoloads/SettingsManager.gd` — `apply_locale_settings()` carga
   `ui_strings.en.translation` y **fabrica** el `es` en runtime copiando las claves.
   No hay camino para una tercera `.translation`.
3. `core_v2/ui/OptionsMenu.gd` — arma la lista a mano:
   `Auto / Español / English` (índices 0/1/2) y `_on_language_selected()` mapea
   0→auto, 1→es, 2→en. Falta el ítem y su índice.
4. `project.godot` §`[locale]` (línea ~3203) — `fallback="es"` y
   `translations=PoolStringArray("res://locale/ui_strings.en.translation")`.
   Solo está registrada la `en`.

## Solution

### §1. Arreglar el extractor primero (bloqueador 2)

`tools/i18n_extract.py` pasa a ser **N-columnas agnóstico**:

- `load_existing_csv()` devuelve el **row completo** (todas las columnas), no solo `en`.
- `save_csv()` **preserva** el header existente y toda columna que no sea
  `keys`/`es`, en su orden. Las columnas nuevas se preservan aunque el script no
  las entienda.
- Comportamiento por defecto (CSV de 3 columnas) **idéntico al de hoy**: mismo
  output byte a byte. Este es el test que decide — el pipeline de FD-303 no puede
  cambiar de resultado.
- Test: `core_v2/tests/test_i18n_extract.py` (ya existe) se extiende con un caso
  que corre el extractor sobre un CSV con columna `pt_BR` y verifica que la
  columna **sobrevive** con sus valores.

**Sin esto, todo lo demás es frágil.**

### §2. La columna y el código de locale

- **Encabezado del CSV: `pt_BR`** (no `pt`). Godot usa el formato
  `idioma_PAÍS`; así `OS.get_locale()` (`"pt_BR"` en un sistema brasileño)
  coincide sin traducción.
- Nueva columna al final: `keys,es,en,pt_BR`.
- `locale/ui_strings.pt_BR.translation` generada por el importer CSV de Godot.
- **Verificar** que `locale/ui_strings.csv.import` reconozca la nueva columna
  (hoy su `files=[...]` solo lista la `en`) y regenerar si hace falta.

### §3. Contenido: 347 strings

`locale/ui_strings.csv` tiene 347 filas. La traducción es **español → portugués de
Brasil**. Reglas:

- **pt-BR, no pt-PT.** "Tela" no "ecrã"; "Arquivo" no "ficheiro"; "Você" no "Tu"
  (Brasil usa `você` como tratamento padrão).
- **Mantener los placeholders** (`%d`, `%s`, `%.1f`, `%02d`) y las secuencias de
  escape tal cual. El extractor ya soporta multilínea (hay entradas con `\n`).
- **No traducir** términos diegéticos que son nombres propios del juego: `Cargol`,
  `Elías`, `Odisea`, `DDC`, `OdiseaOS`, `SuitOS`, `Criogenia`, `Cliocápsulas`.
- Las claves **son** el texto en español (`keys` = `es`). La columna `es` se deja
  intacta (el sistema la usa como fallback y como identidad de la clave).

### §4. Cablear el idioma (bloqueador 3)

Cinco puntos, todos chicos:

1. **`resolve_effective_language()`** — agregar la rama:
   `pt` (o `pt_BR`) → `"pt_BR"`. Mantener el resto igual.
2. **`apply_locale_settings()`** — generalizar la carga: si existe
   `ui_strings.<code>.translation`, cargarla. El caso `es` (clave = texto)
   se puede seguir fabricando, o dejar de fabricarlo si el CSV ya trae la `es`.
3. **`OptionsMenu`** — agregar `"Português (Brasil)"` a la lista y su índice en
   `_load_ui_values()` y `_on_language_selected()`. Orden sugerido:
   `Auto / Español / English / Português (Brasil)`.
4. **`project.godot` §`[locale]`** — sumar `ui_strings.pt_BR.translation` a
   `translations`.
5. **`test_i18n.gd`** — nuevos asserts: `pt_BR` traduce, `auto` en un sistema
   `pt_BR` resuelve a `pt_BR`, y la clave faltante cae a la clave (fallback).

### §5. La fuente (bloqueador 1) — **F2, decisión de Sebastián**

Verificado: **7 de las 8 fuentes cubren pt-BR completo. La única que falla es
`Ac437_OlivettiThin_8x16.ttf`** (la de `TinyFont.tres`), a la que le faltan
los 13 caracteres de arriba.

Opciones, de menor a mayor costo:

- **(a) Fallback de fuente para `TinyFont`.** Godot 3 **no** tiene fallback nativo
  por `DynamicFont`. Pero se puede **fusionar** una fuente que sí tenga los glifos
  con `Ac437` usando `fontTools.merge` y regenerar un solo TTF. Costo: un script
  de build, sin dibujar nada. **Recomendada.**
- **(b) Parchear los 13 glifos a mano.** Dibujarlos en el estilo 8x16 de Ac437.
  Más fiel, pero es trabajo de arte tipográfico.
- **(c) Cambiar `TinyFont.tres` a otra fuente.** Trivial, pero cambia el look del
  texto chico (probablemente inaceptable: es el look retro).
- **(d) No hacer nada.** Aceptar tofu en `ã`/`õ` de overlays y subtítulos.
  Descartada.

Este FD **entrega F1 (pipeline + traducción + cableado) sin la fuente**, y deja F2
(fuente) como ticket aparte. Decisión pendiente — ver Open Question 1.

### §6. Determinismo

Ninguna de estas claves viaja por el stream de input (`InputDataV2`). El idioma es
configuración local (`SettingsManager`), igual que hoy. **El replay no cambia.**

## Considered Options

- **Columna `pt_BR` en el mismo CSV (elegida).** Un solo pipeline, una sola
  fuente de verdad, el extractor ya existe.
- **CSV separado por idioma.** Descartada: duplica el extractor y el problema de
  sincronización.
- **`pt` en vez de `pt_BR`.** Descartada: se pierde la coincidencia automática con
  `OS.get_locale()` y obliga a mapear a mano.
- **Delegar la traducción sin arreglar el extractor.** Descartada: la columna se
  borraría en el primer commit que toque un string (§1).

## Fuera de scope

- **Portugués de Portugal (pt_PT).** Si aparece, es otra columna.
- **Fuentes no-latinas** (coreano, chino, árabe, cirílico). Sigue parkeado en
  `FEATURE_INDEX.md` con su bloqueador.
- **Voces PT-BR** (locución). Solo texto.
- **Traducir los diálogos dinámicos de la IA Odisea**, que no están en el CSV —
  mismo agujero que ya documentó FD-303.
- **F2 (fuente)**: ticket aparte (§5).

## Files to Modify

- `tools/i18n_extract.py` — N-columnas (§1).
- `core_v2/tests/test_i18n_extract.py` — caso de preservación de columna (§1).
- `locale/ui_strings.csv` — columna `pt_BR` (§2, §3).
- `locale/ui_strings.pt_BR.translation` — generada por el importer (§2).
- `locale/ui_strings.csv.import` — verificar/regenerar (§2).
- `core_v2/autoloads/SettingsManager.gd` — `resolve_effective_language()` +
  `apply_locale_settings()` (§4).
- `core_v2/ui/OptionsMenu.gd` — ítem de menú + índices (§4).
- `project.godot` — §`[locale]` `translations` (§4).
- `core_v2/tests/test_i18n.gd` — asserts `pt_BR` (§4).
- `docs/features/FEATURE_INDEX.md` — alta de FD-308 (modificar).

**F2 (aparte):** `assets/fonts/Ac437_OlivettiThin_8x16.ttf` o `TinyFont.tres`,
según la opción elegida en §5.

## Verification

1. **Extractor no destructivo.** Correr `tools/i18n_extract.py` sobre el CSV de
   4 columnas **no** altera la columna `pt_BR`. Y sobre el CSV de 3 columnas, el
   output es **idéntico** al de hoy (regresión de FD-303).
2. **Traducción viva.** Con `set_locale("pt_BR")`, `tr("NUEVA PARTIDA")` devuelve
   la cadena en portugués.
3. **`auto` en un sistema brasileño.** `OS.get_locale()` en `pt_BR` +
   `ui_language = "auto"` → `TranslationServer.get_locale() == "pt_BR"`.
4. **Menú.** Opciones muestra "Português (Brasil)", y al elegirlo el UI cambia
   en caliente.
5. **Placeholders intactos.** Ninguna cadena traducida pierde su `%d`/`%s`.
   Script de verificación: contar placeholders por fila entre `es` y `pt_BR`.
6. **Cobertura de las 347 filas.** Ninguna queda vacía en `pt_BR`.
7. **Fuentes (F2).** `tools/check_glyph_coverage.py` (nuevo, ver abajo) reporta
   pt-BR **OK** para toda fuente que el juego use para texto traducible.
8. **Replay.** Un replay grabado antes del cambio reproduce igual (el idioma no
   entra al stream).

## Herramienta nueva: `tools/check_glyph_coverage.py`

Se agrega al repo (ya escrito y verificado en esta sesión). Verifica la
cobertura de glifos de una fuente leyendo la tabla `cmap`, sin dependencias
(fontTools opcional, si está lo usa):

```
python3 tools/check_glyph_coverage.py        # pt-BR
python3 tools/check_glyph_coverage.py --ko   # Hangul (para el caso parkeado)
```

Sirve para que el próximo idioma no se descubra leyendo `fc-query` a mano.
Ideal: sumarlo a `asset_integrity.yml` como paso opcional.

## Open Questions

1. **Fuente (§5).** ¿Vamos por la fusión con `fontTools.merge` (opción a,
   recomendada), por dibujar los 13 glifos (b), o por cambiar `TinyFont` (c)?
   Es la única decisión que no puedo tomar por ti, porque toca el look.
2. **¿El portugués es para una audiencia real** (como el inglés, que salió de la
   primera prueba pública) o preventivo? Cambia la prioridad de F2.
3. **¿`es` deja de fabricarse en runtime?** Hoy `SettingsManager` crea el `es`
   copiando claves porque el CSV nunca trajo una `es` real. Si el pipeline pasa a
   N-columnas, se puede simplificar. Cambio de comportamiento: prefiero
   preguntarlo antes de tocarlo.


---

## Implementado — correcciones a este diseño (2026-09-19, FD-309)

Se entregó junto con el coreano. Tres cosas de este documento resultaron falsas o
innecesarias al ejecutarlo:

1. **§5 se equivoca: Godot 3 SÍ tiene fallback de fuente.** `DynamicFont` expone
   `fallback/N` / `add_fallback()` y `DynamicFontAtSize::_find_char_with_font()`
   recorre los fallbacks. No hizo falta `fontTools.merge` (opción a), ni dibujar
   los 13 glifos (b), ni cambiar `TinyFont` (c). Una fuente de respaldo declarada
   en los 17 `DynamicFont` del proyecto tapa los 13 acentos faltantes de Ac437 sin
   tocar Ac437 ni el look del texto chico. Lo aplica
   `tools/add_font_fallback.py --check`.
2. **§1 se hizo tal cual.** El extractor es N-columnas y hay test de regresión
   byte a byte para el caso de 3 columnas.
3. **Open Question 3 resuelta: el `es` deja de fabricarse.** Con `compress=true`
   el importer produce `PHashTranslation`, que no expone `get_message_list()`, así
   que la fabricación era inviable; y es innecesaria, porque el CSV trae columna
   `es` y el importer genera su `.translation`.

Open Question 1 (qué opción de fuente) queda contestada por (1). Open Question 2
(audiencia real) sigue abierta, pero ya no bloquea nada.

El CSV tiene **289 filas**, no 347: el conteo de este FD era de una versión previa.
