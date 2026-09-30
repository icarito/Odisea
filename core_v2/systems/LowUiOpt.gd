extends Reference

# FD-316 (tarea GG): interruptor unico de los ahorros de UI del tier LOW.
#
# El HUD 2D cuesta ~15 ms por frame en el Anbernic (render-esclavo, medido con las sondas de
# PlaybackProbes). Estos arreglos solo aplican al perfil LOW y se pueden apagar en el mismo
# device para el A/B:
#   - controles tactiles que no se dibujan hasta el primer toque real (el hint del SO mentia
#     en el Anbernic FRT/SDL y los instanciaba igual),
#   - widgets y Viewports de HUD animados a ~10 Hz (UPDATE_ONCE periodico) en vez de cada frame,
#   - shaders de CanvasItem caros (viñetas de pantalla completa) con la variante sin SCREEN_TEXTURE,
#   - fuentes con sombra dinamica (subtitulos) sin sombra.
#
# ODISEA_LOW_UI_OPT=0 los apaga; unset o 1 los deja activos. Fuera del tier LOW no cambian nada.

const ENV := "ODISEA_LOW_UI_OPT"
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

# El A/B por entorno manda sobre el tier: 0 apaga aunque el gate este en LOW.
static func env_off() -> bool:
	return OS.get_environment(ENV).strip_edges() == "0"

# Resuelve el gate por el arbol (mismo camino que HudViewMount.widget_alpha) para poder
# usarse tambien desde scripts que no son Node.
static func gate_low() -> bool:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return false
	var gate = (loop as SceneTree).root.get_node_or_null("GLES3VendorGate")
	return gate != null and gate.has_method("is_low_tier") and bool(gate.is_low_tier())

# Arreglos de UI activos: tier LOW y sin el A/B apagado.
static func enabled() -> bool:
	return not env_off() and gate_low()
