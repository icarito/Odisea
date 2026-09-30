extends Reference

# FD-316: interruptores de los ahorros de UI del tier LOW.
#
# El HUD 2D cuesta ~15 ms por frame en el Anbernic (render-esclavo, medido con las sondas de
# PlaybackProbes). Cada arreglo se puede apagar por separado en el mismo device para el A/B,
# con su propia env; el maestro ODISEA_LOW_UI_OPT sigue mandando sobre todos:
#   - ODISEA_LOW_UI_OPT=0 apaga todos los ahorros, =1 los enciende todos (A/B de benchmark);
#     sin definir manda el env de cada interruptor y, si tampoco esta, su default.
#   - ODISEA_LOW_UI_TOUCH_LAZY (tarea II): controles tactiles solo tras el primer toque real
#     (el hint del SO mentia en el Anbernic FRT/SDL). Default ON; no cambia el aspecto.
#   - ODISEA_LOW_UI_TERMINAL_RES (tarea MM): pantallas de terminal a 1/3 de resolucion.
#     Default OFF.
#   - ODISEA_LOW_UI_VIEWPORT_HZ (tareas KK/MM): Viewports/pantallas visibles a ~10 Hz en vez
#     de cada frame. Default OFF.
#   - ODISEA_LOW_UI_IMGUI_NO_INPUT_REBUILD (tarea NN): ImGui sin rearme por input (solo lo
#     arma update_hz). Default OFF.
#
# Los ahorros base (tarea GG) que no tienen interruptor propio siguen al maestro: sombra de
# subtitulos, variante barata de la viñeta, HUD animado a 10 Hz y el Viewport animado del HUD.
# Fuera del tier LOW nada de esto cambia nada.

const ENV := "ODISEA_LOW_UI_OPT"
const ENV_TOUCH_LAZY := "ODISEA_LOW_UI_TOUCH_LAZY"
const ENV_TERMINAL_RES := "ODISEA_LOW_UI_TERMINAL_RES"
const ENV_VIEWPORT_HZ := "ODISEA_LOW_UI_VIEWPORT_HZ"
const ENV_IMGUI_NO_INPUT_REBUILD := "ODISEA_LOW_UI_IMGUI_NO_INPUT_REBUILD"

# Defaults de cada interruptor en tier LOW, sin env ni maestro. Los que cambian el aspecto
# quedan apagados; el tactil perezoso (invisible) queda prendido.
const TOUCH_LAZY_DEFAULT := true
const TERMINAL_RES_DEFAULT := false
const VIEWPORT_HZ_DEFAULT := false
const IMGUI_NO_INPUT_REBUILD_DEFAULT := false

# Frecuencia de refresco de la UI animada en LOW (la "receta de 10 Hz" del HUD).
const HZ := 10.0
const INTERVAL := 1.0 / HZ

# FD-316 (tarea MM): escala de la resolucion del Viewport de las pantallas de terminal en
# tier LOW. El Viewport nominal (p.ej. 1280x800) es mas grande que la pantalla entera del
# handheld y re-renderizarlo cuesta ~9.5 ms por frame aun a 10 Hz. Dibujar a un tercio
# (~426x266, o ~320x200 si el nominal es chico) recorta el fillrate ~9x y la UI, que se
# dibuja relativa a rect_size, se lee igual. El clamp historico de movil/web (0.35) la
# lleva a ese orden; queda como constante para el A/B y los tests.
const VIEWPORT_SCALE := 1.0 / 3.0

# ImGuiCanvas (CryoPodImGui, Flashlight*, Protocol*, DebugHud*): update_hz ya espacia el
# frame de ImGui, pero input_hz > 0 lo vuelve a armar mientras haya input reciente (250 ms);
# en el handheld hay input casi continuo (stick/pad), asi que a 30 Hz el frame se rearma
# casi cada tick y sube geometria igual. Con ODISEA_LOW_UI_IMGUI_NO_INPUT_REBUILD se apaga
# (0): el unico refresco es el periodico de update_hz.
const IMGUI_INPUT_HZ := 30.0

# Valor crudo de una env: 0/1 explicito, -1 sin definir.
static func _flag(env: String) -> int:
	var v := OS.get_environment(env).strip_edges()
	if v == "0":
		return 0
	if v == "1":
		return 1
	return -1

# El A/B clasico: ODISEA_LOW_UI_OPT=0 apaga todos los ahorros.
static func env_off() -> bool:
	return _flag(ENV) == 0

# Un interruptor: activo solo en tier LOW. Con el maestro definido el maestro manda (0 apaga
# todos, 1 enciende todos); si no, manda su env propio y, si tampoco esta, su default.
static func _switch(env: String, default_on: bool) -> bool:
	if not gate_low():
		return false
	var master := _flag(ENV)
	if master == 0:
		return false
	if master == 1:
		return true
	var own := _flag(env)
	if own == 0:
		return false
	if own == 1:
		return true
	return default_on

# Tarea II: sin un touch real visto los controles tactiles no se dibujan ni procesan.
static func touch_lazy() -> bool:
	return _switch(ENV_TOUCH_LAZY, TOUCH_LAZY_DEFAULT)

# Tarea MM: pantallas de terminal a 1/3 de resolucion en LOW.
static func terminal_res() -> bool:
	return _switch(ENV_TERMINAL_RES, TERMINAL_RES_DEFAULT)

# Tareas KK/MM: Viewports/pantallas visibles a ~10 Hz en vez de cada frame.
static func viewport_hz() -> bool:
	return _switch(ENV_VIEWPORT_HZ, VIEWPORT_HZ_DEFAULT)

# Tarea NN: el input deja de rearmar el frame de ImGui; solo lo arma update_hz.
static func imgui_no_input_rebuild() -> bool:
	return _switch(ENV_IMGUI_NO_INPUT_REBUILD, IMGUI_NO_INPUT_REBUILD_DEFAULT)

# ImGuiCanvas (CryoPodImGui, Flashlight*, Protocol*, DebugHud*): en LOW con el interruptor
# activo devuelve 0 (sin rearme por input); fuera de LOW o apagado conserva la tasa pedida.
static func imgui_input_hz(base: float = IMGUI_INPUT_HZ) -> float:
	return 0.0 if imgui_no_input_rebuild() else base

# Resuelve el gate por el arbol (mismo camino que HudViewMount.widget_alpha) para poder
# usarse tambien desde scripts que no son Node.
static func gate_low() -> bool:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return false
	var gate = (loop as SceneTree).root.get_node_or_null("GLES3VendorGate")
	return gate != null and gate.has_method("is_low_tier") and bool(gate.is_low_tier())

# Ahorros base del tier LOW sin interruptor propio (tarea GG). Siguen al maestro: =0 los
# apaga, unset o 1 los deja activos.
static func enabled() -> bool:
	return not env_off() and gate_low()
