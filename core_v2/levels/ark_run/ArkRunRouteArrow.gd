extends Reference

# FD-325 polish — línea de rumbo del HUD diegético. Funciones puras, sin nodos:
# elige la flecha según dónde cae el objetivo en pantalla y arma el texto
# "◄ MOTOR · 1240 m" / "▲ MOTOR · 1240 m ▲" / "MOTOR · 1240 m ►".

const LEFT_FRAC := 0.42
const RIGHT_FRAC := 0.58

# `screen`: posición proyectada del objetivo; `view`: tamaño del viewport.
static func arrow_for(screen: Vector2, view: Vector2) -> String:
	if view.x <= 0.0:
		return ""
	if screen.x < view.x * LEFT_FRAC:
		return "left"
	if screen.x > view.x * RIGHT_FRAC:
		return "right"
	return "center"

# Arma el texto de rumbo a partir del texto base ("MOTOR · 1240 m") y la flecha.
static func format_route(text: String, arrow: String) -> String:
	if text == "":
		return ""
	if arrow == "left":
		return "◄ " + text
	if arrow == "right":
		return text + " ►"
	if arrow == "center":
		return "▲ " + text + " ▲"
	return text
