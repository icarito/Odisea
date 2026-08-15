extends Spatial
class_name CoolantFogAdapter

# CoolantFogAdapter.gd - Translates CoolantLeak intensity into GasArea3D fog density (FD-255 J7).
# Keeps particle count proportional to leak intensity and ensures cold gas blinds without causing damage.

# --- EXPORTED PROPERTIES ---
# CoolantLeak node providing leak state and intensity
export(NodePath) var leak_path: NodePath
# GasArea3D node displaying the coolant fog
export(NodePath) var gas_path: NodePath
# Maximum active gas particles at full leak intensity
export(int) var particles_at_full: int = 90
# Horizontal radius of the fog volume around the adapter
export(float) var fill_radius: float = 2.2
# Vertical height of the fog volume around the adapter
export(float) var fill_height: float = 1.4
# Rate at which fog particles dissipate when leak is sealed
export(float) var dissipate_rate: float = 0.6
# Tamaño de cada partícula de niebla. Es la perilla que decide si la nube CIEGA o si se
# ve como motas: estaba fija en el código y ninguna configuración del manager la alcanzaba.
export(float) var particle_scale: float = 3.0
# Cuánto vive cada partícula. Más largo = nube más densa a igual ritmo de emisión.
export(float) var particle_lifetime: float = 8.0
# Segundos que tarda la nube en llenarse del todo. Estaba fijo en 0.5 s, y a esa velocidad
# la niebla aparecía de golpe: se leía como una explosión, no como una fuga que crece.
export(float) var fill_duration: float = 3.0

# --- INTERNAL STATE ---
var _emit_counter: int = 0


func _ready() -> void:
	add_to_group("replay_sync")
	_enforce_no_damage()


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return

	var leak: Node = _resolve_leak()
	if leak == null or not leak.has_method("get_leak_intensity"):
		return

	var gas: Node = get_node_or_null(gas_path)
	if gas == null:
		return

	_enforce_no_damage_on_gas(gas)

	var manager: Node = gas.get("manager")
	if manager == null:
		manager = gas.get_node_or_null("GasParticleManager")
	if manager == null:
		return

	if "decay_rate" in manager:
		manager.set("decay_rate", dissipate_rate)

	var intensity: float = clamp(float(leak.call("get_leak_intensity")), 0.0, 1.0)
	var active_indices: Array = manager.call("get_active_particle_indices")
	var current_count: int = active_indices.size()

	if intensity <= 0.0:
		if current_count > 0:
			manager.call("clear_all")
		return

	var target_count: int = int(round(intensity * float(particles_at_full)))
	if current_count < target_count:
		var needed: int = target_count - current_count
		var max_per_frame: int = int(max(1, ceil(float(particles_at_full) * delta / max(fill_duration, 0.05))))
		var to_emit: int = int(min(needed, max_per_frame))
		_emit_particles(manager, to_emit)


# --- INTERNAL HELPERS ---

func _enforce_no_damage() -> void:
	var gas: Node = get_node_or_null(gas_path)
	if gas != null:
		_enforce_no_damage_on_gas(gas)


func _enforce_no_damage_on_gas(gas: Node) -> void:
	# Cold coolant fog blinds the player but does not inflict contact damage (FD-256).
	if float(gas.get("damage_per_second")) != 0.0:
		gas.set("damage_per_second", 0.0)


func _resolve_leak() -> Node:
	if leak_path == null or leak_path.is_empty():
		return null
	return get_node_or_null(leak_path)


func _emit_particles(manager: Node, count: int) -> void:
	for _i in range(count):
		_emit_counter += 1
		var rx := (_hashed_unit(_emit_counter) - 0.5) * 2.0 * fill_radius
		var ry := (_hashed_unit(_emit_counter + 1013) - 0.5) * fill_height
		var rz := (_hashed_unit(_emit_counter + 7919) - 0.5) * 2.0 * fill_radius
		var local_pos := Vector3(rx, ry, rz)
		var world_pos: Vector3 = global_transform.xform(local_pos)
		var manager_pos: Vector3 = manager.global_transform.xform_inv(world_pos)
		manager.call("emit_particle", manager_pos, Vector3.ZERO, particle_lifetime, particle_scale)


func _hashed_unit(index: int) -> float:
	var h := int(index) & 0x7fffffff
	h = ((h >> 15) ^ h) * 0x2c1b3c6d
	h = h & 0x7fffffff
	h = ((h >> 12) ^ h) * 0x297a2d39
	h = h & 0x7fffffff
	h = (h >> 15) ^ h
	return float(h & 0x7fffffff) / 2147483647.0


# --- SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"emit_counter": _emit_counter
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("emit_counter"):
		_emit_counter = int(data["emit_counter"])
