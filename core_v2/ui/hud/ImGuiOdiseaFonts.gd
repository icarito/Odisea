class_name ImGuiOdiseaFonts

# ImGuiOdiseaFonts.gd - Helper compartido de tipografia para las piezas ImGui de Odisea
# (CryoPodImGui, Flashlight{Widget,Screen}ImGui, DebugHud{Widget,Screen}ImGui).
#
# Regla (cambio de criterio post-CryoPod): el TITULO de cada pieza sigue en Sixtyfour
# (Heading_Font.tres original de CryoPodUI.gd, 36px) -- el RESTO del texto (cuerpo,
# numeros) pasa a la fuente default de ImGui (ProggyClean), que se lee mas clara que
# Silkscreen a estos tamanos chicos.
#
# ProggyClean es bitmap, horneada a 13px: escalarla a un tamano que no sea multiplo de
# 13 la deja borrosa (ver round_body_size). Silkscreen (TTF vectorial) no tiene ese
# problema, y sigue siendo el fallback en el binario pinneado hoy (v0.5.4-nightly1), que
# todavia no tiene ImGuiCanvas.add_font_default() -- ese metodo (mas el 3er parametro
# glyph_ranges de add_font) llega en v0.5.4-nightly2.
#
# Coreano: TranslationServer.get_locale() empieza con "ko" -> Sixtyfour no tiene Hangul
# (rompe el titulo) y ProggyClean tampoco -> titulo Y cuerpo van en DungGeunMo
# (assets/fonts/DungGeunMo.ttf, cubre U+AC00-D7A3), con glyph_ranges "korean" cuando el
# motor lo soporta (add_font_default() como senal de que nightly2 tambien trae el rango).

const SIXTYFOUR := "res://assets/Sixtyfour-Regular.ttf"
const DUNGGEUNMO := "res://assets/fonts/DungGeunMo.ttf"
const SILKSCREEN := "res://assets/fonts/Silkscreen-Regular.ttf"

# T12: tamano UNICO para los widgets de slot (linterna, sistemas -- FlashlightWidgetImGui,
# DebugHudWidgetImGui), distinto del de las pantallas grandes (esas siguen pasando su propio
# body_px/title_px a setup(), no tocan esta constante). Antes 14.0 en los dos: a esa medida
# ProggyClean (bitmap horneada a 13px, ver round_body_size) redondeaba PARA ABAJO a 13, mas
# chico que lo pedido. 16.0 sigue redondeando a 13 en cuerpo/numeros (el proximo escalon
# nitido es 26, el doble: no entra en el panel de 210x72/80 sin romper el layout de
# FlashlightWidget/DebugHudWidget), pero el titulo (Sixtyfour, vectorial) si crece un poco y
# el cuerpo se lee mas grande aunque pierda algo de la nitidez "pixel perfect" del bitmap --
# tradeoff aceptado a proposito por legibilidad en el handheld. No cambia PANEL_SIZE: el
# marco del slot y el ancho en el Anbernic (640x480) quedan igual.
const WIDGET_FONT_PX := 16.0


static func _is_korean() -> bool:
	return TranslationServer.get_locale().begins_with("ko")


# Solo tiene sentido para tamanos que van a ProggyClean (ver setup()): redondea al
# multiplo de 13px mas cercano (minimo 13) para que el bitmap no salga borroso al
# escalarlo.
static func round_body_size(px: float) -> float:
	return max(13.0, round(px / 13.0) * 13.0)


# canvas: un ImGuiCanvas ya en _ready() (add_font/add_font_default disponibles).
# body_px/numbers_px/title_px: tamanos PEDIDOS por rol (numbers_px < 0 => = body_px).
# Devuelve {title=idx, body=idx, numbers=idx} para push_font/pop_font y
# set_default_font(fonts.body). Los indices nunca son negativos (caen al de cuerpo, y
# ese al primero que haya cargado bien, igual que los _ready() de antes).
static func setup(canvas, body_px: float, numbers_px: float = -1.0, title_px: float = 36.0) -> Dictionary:
	var korean := _is_korean()
	var has_default: bool = canvas.has_method("add_font_default")
	var n_px := numbers_px if numbers_px > 0.0 else body_px
	var fonts := {}

	if korean:
		if has_default:
			fonts.title = canvas.add_font(DUNGGEUNMO, title_px, "korean")
			fonts.body = canvas.add_font(DUNGGEUNMO, body_px, "korean")
			fonts.numbers = canvas.add_font(DUNGGEUNMO, n_px, "korean")
		else:
			# Motor de hoy: sin rango "korean" declarado, DungGeunMo entra con el rango
			# default (Latin). Sigue siendo mejor que un "?" en Sixtyfour; el Hangul
			# llega con nightly2.
			fonts.title = canvas.add_font(DUNGGEUNMO, title_px)
			fonts.body = canvas.add_font(DUNGGEUNMO, body_px)
			fonts.numbers = canvas.add_font(DUNGGEUNMO, n_px)
	else:
		fonts.title = canvas.add_font(SIXTYFOUR, title_px)
		if has_default:
			fonts.body = canvas.add_font_default(round_body_size(body_px))
			fonts.numbers = canvas.add_font_default(round_body_size(n_px))
		else:
			fonts.body = canvas.add_font(SILKSCREEN, body_px)
			fonts.numbers = canvas.add_font(SILKSCREEN, n_px)

	if fonts.body < 0:
		fonts.body = fonts.title
	if int(fonts.title) < 0:
		fonts.title = fonts.body
	if int(fonts.numbers) < 0:
		fonts.numbers = fonts.body
	return fonts


# Para pantallas con mas de dos tamanos de "cuerpo" (p.ej. el estado grande 36px y el
# porcentaje 26px de FlashlightScreenImGui, o el subtitulo chico de DebugHudScreenImGui):
# un tamano extra con la misma regla de familia que setup().body (ProggyClean/Silkscreen,
# DungGeunMo en coreano). Usar junto a setup() para el resto de roles.
static func add_body_size(canvas, size_px: float) -> int:
	if _is_korean():
		var has_default: bool = canvas.has_method("add_font_default")
		return canvas.add_font(DUNGGEUNMO, size_px, "korean") if has_default else canvas.add_font(DUNGGEUNMO, size_px)
	if canvas.has_method("add_font_default"):
		return canvas.add_font_default(round_body_size(size_px))
	return canvas.add_font(SILKSCREEN, size_px)
