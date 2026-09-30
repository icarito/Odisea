extends Node

# LowHzViewportRedraw.gd - FD-316 (tarea GG): mantiene un Viewport de HUD animado a ~10 Hz
# (UPDATE_ONCE periodico) en tier LOW, en vez de UPDATE_ALWAYS cada frame. El Viewport se
# instala en UPDATE_DISABLED y este nodo lo despierta un frame por intervalo: el contenido
# de la pantalla sigue leyendose vivo sin re-renderizar 60 veces por segundo.
# Solo se instala cuando LowUiOpt esta activo (ver HudViewMount): fuera del tier el Viewport
# queda en UPDATE_ALWAYS como siempre.

const LowHzTickScript = preload("res://core_v2/systems/LowHzTick.gd")

var viewport: Viewport = null
var _low_hz = LowHzTickScript.new()

func _process(delta: float) -> void:
	if not is_instance_valid(viewport):
		queue_free()
		return
	if _low_hz.step(delta) < 0.0:
		return
	viewport.render_target_update_mode = Viewport.UPDATE_ONCE
