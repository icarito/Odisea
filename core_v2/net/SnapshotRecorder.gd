extends Node

# SnapshotRecorder.gd - FD-316 (tarea DD): grabador de la traza de snapshots del
# render-esclavo. Durante un replay de desktop captura, por tick, el MISMO dict que
# RemoteSimHost.capture_snapshot arma, pero sobre el nivel en current_scene y sin sim
# host ni red. Al terminar lo vuelca en un unico archivo binario (SnapshotTrace), que el
# Anbernic reproduce solo-render (ODISEA_SNAPSHOT_PLAYBACK) para medir el costo de render
# sin pagar la simulacion local.
#
# Reusa RemoteSimHost en vez de duplicar la captura: el host ya sabe leer transform/
# visibilidad/luz, la cadena del rig, el len del arm, la interaccion y los estados de
# los actores. Aca solo se le dice "el nivel simulado es el current_scene del replay":
# con eso los paths de entidad quedan relativos al nivel, igual que en el offload real.

const RemoteSimHostScript = preload("res://core_v2/net/RemoteSimHost.gd")
const SnapshotTraceScript = preload("res://core_v2/net/SnapshotTrace.gd")

# Paso de emision de la traza. El playback alimenta a 30 Hz con paso 2 sobre los 60 Hz
# grabados: el mismo contrato del offload real (RemoteSimHost.snapshot_every_n_ticks=2).
const TRACE_SNAP_STEP := 2

var _host = null
var _snapshots: Array = []
var _path := ""
var _active := false

# Arranca la grabacion. Devuelve false si ya habia una activa.
func begin(path: String) -> bool:
	if _active:
		return false
	_host = RemoteSimHostScript.new()
	_host.name = "SnapshotRecorderHost"
	add_child(_host)
	# RemoteSimHost.capture_snapshot lee el paso de los globals para que el esclavo
	# calibre su retardo de interpolacion. El playback usa paso 2.
	_host._active_snap_step = TRACE_SNAP_STEP
	_path = path
	_snapshots = []
	_active = true
	print("[SnapshotRecorder] grabando traza de snapshots en ", path)
	return true

func is_active() -> bool:
	return _active

# Captura el estado de ESTE tick. Se llama despues del step del jugador (mismo instante
# que captura la autoridad real: antes, camara/rig llegan un tick atrasados).
func capture(tick: int) -> void:
	if not _active or _host == null:
		return
	var tree = get_tree()
	if tree == null:
		return
	# El "nivel de simulacion" es el current_scene del replay: el host filtra las
	# entidades a ese subarbol y arma paths relativos a el, como en el offload.
	_host._sim_level = tree.current_scene if tree.current_scene != null else null
	_host._current_tick = tick
	var snap = _host.capture_snapshot()
	if snap is Dictionary and not snap.empty():
		_snapshots.append(snap)

# Vuelca la traza completa y libera el host. Devuelve false si no habia snapshots.
func finish() -> bool:
	if not _active:
		return false
	var count := _snapshots.size()
	var ok := count > 0 and SnapshotTraceScript.write(_path, _snapshots)
	_teardown()
	return ok

func _teardown() -> void:
	_snapshots = []
	_active = false
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
	_host = null
