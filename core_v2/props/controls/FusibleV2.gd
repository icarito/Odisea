extends HoldInteractableV2
class_name FusibleV2

# FusibleV2.gd — fusible con socket (FD-289 §7.6, T5).
#
# Prop faltante del vocabulario de máquinas: mientras el jugador sostiene la interacción
# el fusible se desliza fuera de su socket, y se vuelve a deslizar dentro si lo sostiene
# de nuevo. El verbo es mantener, no accionar de un golpe (misma familia que
# PressurePump/PurgeTuner): el esfuerzo dura y se ve durar.
#
# El estado de gameplay es binario y determinista: installed (is_active = true) o
# removed (is_active = false). No hay reloj de pared ni randf: la posición la gobierna el
# hold_progress de la base, que corre en _physics_process y sobrevive el replay.
#
# Este prop NO notifica a DomeNetworkStatus: el cableado de las señales fuse_extracted/
# fuse_inserted a la red de energía real es T6/T7. Acá solo se exponen.

# Nodo del fusible que se desplaza dentro/fuera del socket. Por defecto "Fuse".
export(NodePath) var fuse_path: NodePath = NodePath("Fuse")
# Cuánto se desplaza el fusible al extraerse, en espacio local del prop. Por defecto
# sobre el eje Y, que es el eje del cilindro del socket: el fusible sale coaxial.
export(Vector3) var extract_offset: Vector3 = Vector3(0.0, 0.16, 0.0)
# Red de energía que este fusible alimenta. Informativo; el cableado es T6/T7.
export(String) var network_id: String = ""

signal fuse_extracted()
signal fuse_inserted()
signal fuse_state_changed(installed)

var _fuse: Spatial = null
var _fuse_rest: Vector3 = Vector3.ZERO


func _ready() -> void:
	._ready()
	# Un tirón por extracción/inserción; el ciclo puede repetirse (extraer↔insertar).
	hold_duration = 1.2
	release_rate = 1.0
	repeatable = true
	# Verbos por defecto del vocabulario (§3.4); una escena puede sobreescribirlos.
	if interaction_verb_active.strip_edges() == "":
		interaction_verb_active = "Extraer"
	if interaction_verb_inactive.strip_edges() == "":
		interaction_verb_inactive = "Insertar"
	_fuse = get_node_or_null(fuse_path) as Spatial
	if _fuse == null:
		_fuse = get_node_or_null("Fuse") as Spatial
	if _fuse != null:
		_fuse_rest = _fuse.translation
	connect("hold_completed", self, "_on_hold_completed")
	_sync_interaction_text()
	_update_hold_visuals(get_hold_progress())


func _sync_interaction_text() -> void:
	interaction_text = interaction_verb_active if is_active else interaction_verb_inactive


func _on_hold_completed() -> void:
	var installed: bool = not is_active
	is_active = installed
	_sync_interaction_text()
	emit_signal("fuse_state_changed", installed)
	if installed:
		emit_signal("fuse_inserted")
	else:
		emit_signal("fuse_extracted")


func _update_hold_visuals(progress: float) -> void:
	if _fuse == null:
		return
	# installed → extensión 0; removed → extensión 1. Mientras se sostiene, progress barre
	# entre ambos extremos, así que el fusible sale o entra de a poco.
	var extract_t: float = progress if is_active else 1.0 - progress
	_fuse.translation = _fuse_rest + extract_offset * extract_t


func _update_visuals() -> void:
	# La pose del fusible la gobierna el hold, no anim_progress.
	_update_hold_visuals(get_hold_progress())


func get_snapshot() -> Dictionary:
	var snap: Dictionary = .get_snapshot()
	snap["fuse_installed"] = is_active
	snap["network_id"] = network_id
	return snap


func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	if data.has("fuse_installed"):
		is_active = bool(data["fuse_installed"])
	_sync_interaction_text()
	_update_hold_visuals(get_hold_progress())
