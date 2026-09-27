extends HUDableComponent
class_name DebugHudScreen

# DebugHudScreen.gd - Pantalla HUDable "Rendimiento": expone un RESUMEN del colector
# de DebugHud (addons/debug_hud/) al mismo contrato que cualquier otra pantalla de
# SuitOS (FlashlightScreen es el ejemplo minimo, ver core_v2/things/FlashlightScreen.gd).
#
# Por que existe: en gama baja + perfil plano, DebugHud no dibuja nada en el propio
# dispositivo (GLES3VendorGate.is_low_tier() and is_flat_mode()), pero el colector
# sigue corriendo. Esta pantalla es el unico camino por el que esas metricas llegan
# al telefono: SuitOSRemoteBridge ya reenvia widget_snapshot() de toda pantalla
# registrada (coalescido a 10 Hz maximo, ver SCREEN_DATA_FLUSH_INTERVAL en
# core_v2/components/SuitOSRemoteBridge.gd), asi que el telefono la recibe como
# cualquier otro widget de slot -- no hace falta el transporte TCP propio de gdtk.
#
# Tamano: NO se manda el snapshot completo de DebugMetrics (~100 KB con las 600
# muestras de cada serie). Solo latest (6 numeros) + dos series cortas de 20 puntos
# (fps, frame ms) para un sparkline chico -- unos pocos cientos de bytes por envio.
#
# Se instancia como hijo del autoload DebugHud (no de una escena de nivel): es una
# pantalla de sistema, no de un prop del mundo, y debe existir sin importar la escena
# activa (ver DebugHud._ready()).

const SERIES_LEN := 20
const RESAMPLE_INTERVAL := 0.5 # 2 Hz: de sobra para un numero que un humano lee
const WidgetScene := preload("res://core_v2/ui/hud/DebugHudWidget.tscn")

var hud = null # DebugHud (autoload), inyectado por quien instancia esta pantalla
var _accum := 0.0


func _init() -> void:
	hud_screen_id = "system:performance"
	hud_screen_title = "Rendimiento"
	hud_widget_scene = WidgetScene
	default_relevance = 0.05 # baja: es una pantalla de diagnostico, no de gameplay


func _process(delta: float) -> void:
	if hud == null:
		return
	_accum += delta
	if _accum < RESAMPLE_INTERVAL:
		return
	_accum -= RESAMPLE_INTERVAL
	notify_state_changed()


func widget_snapshot() -> Dictionary:
	if hud == null:
		return {"proto": 1, "id": screen_id(), "title": screen_title(), "source": "offline"}
	var s: Dictionary = hud.summary()
	s["proto"] = 1
	s["id"] = screen_id()
	s["title"] = screen_title()
	s["source"] = "online"
	s["fps_series"] = hud.series_tail("TIME_FPS", SERIES_LEN)
	s["frame_ms_series"] = hud.series_tail("TIME_PROCESS", SERIES_LEN)
	return s


# Solo lectura: no hay accion de gameplay que ejecutar desde esta pantalla.
func allowed_actions() -> Array:
	return []


func perform_action(_op: String, _args: Dictionary = {}) -> Dictionary:
	return {"ok": false, "error": "system:performance es solo lectura"}
