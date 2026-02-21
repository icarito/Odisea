# core_v2/components/OYSComponent.gd
extends Node

class_name OYSComponent

const OYS_Interpreter = preload("../systems/OYS_Interpreter.gd")

export(String, FILE, "*.oys") var script_file

var interpreter: OYS_Interpreter
var last_modified_time: int = 0
var _current_path: String = ""
var _player_snapshot: Dictionary = {}
var _initial_snapshot: Dictionary = {} # Snapshot al momento de activar el trigger
var _checkpoint_snapshot: Dictionary = {} # Snapshot del último CheckZone
var _checkpoint_pc: int = -1 # Program counter al pasar por el CheckZone
var _initial_position: Vector3 = Vector3.ZERO
var _initial_yaw: float = 0.0
var _initial_pitch: float = 0.0
var _has_initial_position: bool = false
var _smooth_correction_target: Vector3 = Vector3.ZERO
var _player: KinematicBody = null # Referencia cacheada al jugador
var _smooth_correction_active: bool = false
var _ignore_level_directive: bool = false
const SMOOTH_CORRECTION_SPEED: float = 10.0 # Unidades por segundo

func _ready():
	interpreter = OYS_Interpreter.new(self)
	if script_file != "":
		load_and_start(script_file)
	
	# Conectar a CheckZones para guardar checkpoints durante el script
	_connect_to_checkzones()

# Función centralizada para obtener y cachear la referencia al jugador.
# Esto evita múltiples yields y búsquedas, previniendo condiciones de carrera.
func _get_player() -> KinematicBody:
	if is_instance_valid(_player):
		yield (get_tree(), "idle_frame")
		return _player
	
	# Esperar que el árbol de escenas esté completamente listo
	yield (get_tree(), "idle_frame")
	
	var p = get_parent()
	if not p or not p.is_in_group("player"):
		p = get_tree().get_root().find_node("Pilot", true, false)
	
	if is_instance_valid(p):
		_player = p
	return _player

# Llamado por OYSTrigger para establecer la posición inicial exacta
func set_initial_position(pos: Vector3, yaw: float, pitch: float):
	_initial_position = pos
	_initial_yaw = yaw
	_initial_pitch = pitch
	_has_initial_position = true
	var player = yield (_get_player(), "completed")
	if player:
		print("[OYSComponent] Forzando posición inicial en player: ", player.name)
		# Resetear estado físico completamente para evitar herencia de momento
		if "velocity" in player:
			player.velocity = Vector3.ZERO
		if player.has_method("set_external_velocity"):
			player.set_external_velocity(Vector3.ZERO)

		var t = player.global_transform
		t.origin.x = pos.x
		t.origin.z = pos.z
		player.global_transform = t
	
	# Desactivar corrección suave ya que forzamos posición
	_smooth_correction_active = false
	print("[OYSComponent] Posición inicial forzada: ", pos)

func load_and_start(path: String, start_section: String = "", ignore_level_directive: bool = false):
	_current_path = path
	_ignore_level_directive = ignore_level_directive
	var f = File.new()
	if f.open(path, File.READ) == OK:
		var content = f.get_as_text()
		if _ignore_level_directive:
			content = _strip_level_directive(content)
		last_modified_time = f.get_modified_time(path)
		f.close()

		interpreter.parse(content)

		# Guardar snapshot INICIAL con la posición del trigger
		if _initial_snapshot.empty():
			var player = yield (_get_player(), "completed")
			if player and player.has_method("get_full_snapshot"):
				print("[OYSComponent] Generando snapshot inicial desde player: ", player.name)
				_initial_snapshot = player.get_full_snapshot()
				
				# Si tenemos posición inicial del trigger, usarla
				if _has_initial_position:
					_initial_snapshot["position"] = [_initial_position.x, _initial_position.y, _initial_position.z]
					_initial_snapshot["yaw"] = _initial_yaw
					_initial_snapshot["pitch"] = _initial_pitch
					_initial_snapshot["velocity"] = [0, 0, 0]
				
				print("[OYSComponent] Snapshot INICIAL guardado: pos=", _initial_snapshot.get("position", []))

		call_deferred("_run_and_unpause", start_section)
	else:
		printerr("[OYSComponent] Could not open script: ", path)

func load_and_start_ignoring_level(path: String, start_section: String = "") -> void:
	load_and_start(path, start_section, true)

func _strip_level_directive(content: String) -> String:
	var filtered_lines: Array = []
	for raw_line in content.split("\n"):
		var line := String(raw_line)
		var trimmed := line.strip_edges()
		if trimmed.begins_with("LEVEL ") or trimmed == "LEVEL":
			continue
		filtered_lines.append(line)
	return "\n".join(filtered_lines)

func _run_and_unpause(start_section: String) -> void:
	# DESACTIVAR corrección suave antes de ejecutar el script
	_smooth_correction_active = false
	
	# Restaurar snapshot ANTES de ejecutar el script (para hot-reload)
	if not _player_snapshot.empty():
		var player = yield (_get_player(), "completed")
		if player and player.has_method("restore_snapshot"):
			print("[OYSComponent] Restaurando snapshot en player: ", player.name)
			print("[OYSComponent] Restaurando snapshot ANTES de ejecutar script...")
			
			player.restore_snapshot(_player_snapshot)
			
			# Esperar un frame de física para que la restauración se asiente
			# antes de que el script comience a ejecutarse.
			yield (get_tree(), "physics_frame")
			
			if not is_instance_valid(player): return
			print("[OYSComponent] ✅ Pos restaurada: ", player.global_transform.origin)
		_player_snapshot = {} # Limpiar para no restaurar de nuevo
	
	if not is_inside_tree():
		return
	
	# IMPORTANTE: Resetear stop_requested ANTES de llamar run()
	# (run() lo hace internamente, pero por seguridad)
	interpreter.stop_requested = false
	
	_set_player_pause(true)
	var result = interpreter.run(start_section)
	if result is GDScriptFunctionState:
		yield (result, "completed")
	
	# Solo desactivar pausa si no se solicitó una detención (ej. por hot-reload)
	if not interpreter.stop_requested:
		_set_player_pause(false)

	# Propagar fallo de test al runner
	if interpreter.test_failed:
		push_error("OYS ASSERT FAILED: El test OYS falló en una aserción.")
		# Note: We don't call fail() here as this is not a GdUnitTestSuite.
		# The test runner will detect interpreter.test_failed or the push_error.

# Ejecutar script desde un pc específico (para hot-reload con checkpoint)
func _run_from_pc(from_pc: int) -> void:
	# DESACTIVAR corrección suave antes de ejecutar el script
	_smooth_correction_active = false
	
	# Restaurar snapshot ANTES de ejecutar el script
	if not _player_snapshot.empty():
		var player = yield (_get_player(), "completed")
		if player and player.has_method("restore_snapshot"):
			print("[OYSComponent] Restaurando snapshot (hot-reload) en player: ", player.name)

			print("[OYSComponent] Restaurando snapshot para hot-reload...")
			
			player.restore_snapshot(_player_snapshot)
			
			# Esperar un frame de física para que la restauración se asiente
			# antes de que el script comience a ejecutarse.
			yield (get_tree(), "physics_frame")
			
			if not is_instance_valid(player): return
			print("[OYSComponent] ✅ Pos restaurada: ", player.global_transform.origin)
		_player_snapshot = {}
	
	if not is_inside_tree():
		return
	
	# IMPORTANTE: Resetear stop_requested ANTES de llamar run_from_pc()
	interpreter.stop_requested = false
	
	_set_player_pause(true)
	var result = interpreter.run_from_pc(from_pc)
	if result is GDScriptFunctionState:
		yield (result, "completed")
	
	# Solo desactivar pausa si no se solicitó una detención (ej. por hot-reload)
	if not interpreter.stop_requested:
		_set_player_pause(false)

func _process(_delta):
	# Hot-reload detection
	# Desactivado durante test runs para evitar reloads accidentales.
	var is_test_runner_active = get_tree().get_root().has_node("GdUnitRunner")
	var can_hot_reload = (OS.is_debug_build() or Engine.is_editor_hint()) and not is_test_runner_active
	
	if _current_path != "" and can_hot_reload:
		var f = File.new()
		if f.file_exists(_current_path):
			var mtime = f.get_modified_time(_current_path)
			if mtime > last_modified_time:
				print("[OYSComponent] *** HOT-RELOAD *** Script: ", _current_path)

				# PRIMERO: Detener el intérprete anterior
				interpreter.stop_requested = true
				print("[OYSComponent] Intérprete detenido")

				# Decidir qué snapshot usar: checkpoint o inicial
				var resume_pc: int = 0
				var start_section: String = ""
				
				if not _checkpoint_snapshot.empty():
					# Hay un checkpoint - usar ese y continuar desde ese pc
					_player_snapshot = _checkpoint_snapshot.duplicate(true)
					resume_pc = _checkpoint_pc
					print("[OYSComponent] 📍 Usando CHECKPOINT: pos=", _player_snapshot.get("position", []), " pc=", resume_pc)
				elif not _initial_snapshot.empty():
					# No hay checkpoint - usar snapshot inicial
					_player_snapshot = _initial_snapshot.duplicate(true)
					print("[OYSComponent] Usando snapshot INICIAL: pos=", _player_snapshot.get("position", []))
				
				# Re-parsear el script (puede haber cambiado)
				last_modified_time = mtime
				var content = ""
				if f.open(_current_path, File.READ) == OK:
					content = f.get_as_text()
					if _ignore_level_directive:
						content = _strip_level_directive(content)
					f.close()
				
				interpreter.parse(content)
				
				# REALIZAR HARD RESET antes de relanzar
				hard_reset()
				
				# Si tenemos checkpoint, establecer el pc directamente
				if resume_pc > 0 and resume_pc < interpreter.instructions.size():
					# Buscar la sección que contiene este pc para logging
					for sname in interpreter.section_names:
						if interpreter.sections[sname] <= resume_pc:
							start_section = sname
					print("[OYSComponent] Continuando desde pc=", resume_pc, " (sección: ", start_section, ")")
				
				# Usar call_deferred para ejecutar después de restaurar
				call_deferred("_run_from_pc", resume_pc)

func _physics_process(delta):
	# Corrección suave de posición hacia el centro del trigger
	if _smooth_correction_active:
		var player = _player # Usar la referencia cacheada
		if player:
			var current_pos = player.global_transform.origin
			# Solo corregir X y Z, mantener Y del jugador
			var target = Vector3(_smooth_correction_target.x, current_pos.y, _smooth_correction_target.z)
			var distance = Vector2(current_pos.x - target.x, current_pos.z - target.z).length()
			
			if distance < 0.05: # Llegamos al destino
				_smooth_correction_active = false
				# Posición final exacta
				var t = player.global_transform
				t.origin.x = target.x
				t.origin.z = target.z
				player.global_transform = t
			else:
				# Interpolación suave
				var new_pos = current_pos.linear_interpolate(target, SMOOTH_CORRECTION_SPEED * delta)
				var t = player.global_transform
				t.origin = new_pos
				player.global_transform = t

func _set_player_pause(paused: bool):
	# Usar referencia cacheada. Si no existe, no hacer nada.
	var player = _player
	if player and "is_replay_mode" in player:
		print("[OYSComponent] Setting is_replay_mode=", paused, " en player: ", player.name)
		player.is_replay_mode = paused

# Conectar a todos los CheckZones para capturar checkpoints durante el script
func _connect_to_checkzones():
	if not is_inside_tree():
		return
	yield (get_tree(), "physics_frame") # Esperar a que todos los nodos estén listos
	if not is_inside_tree():
		return # El nodo fue eliminado mientras esperábamos
	var checkzones = get_tree().get_nodes_in_group("CheckZoneV2")
	for cz in checkzones:
		if cz and is_instance_valid(cz) and cz.has_signal("checkpoint_reached"):
			if not cz.is_connected("checkpoint_reached", self, "_on_checkpoint_reached"):
				cz.connect("checkpoint_reached", self, "_on_checkpoint_reached")
				print("[OYSComponent] Conectado a CheckZone: ", cz.name)

# Callback cuando el player pasa por un CheckZone durante la ejecución del script
func _on_checkpoint_reached(_base_transform: Transform):
	if not interpreter or not interpreter.is_running:
		return # Solo guardar checkpoints mientras el script está corriendo
	
	var player = yield (_get_player(), "completed")
	if player and player.has_method("get_full_snapshot"):
		print("[OYSComponent] Guardando checkpoint desde player: ", player.name)
		_checkpoint_snapshot = player.get_full_snapshot()
		_checkpoint_pc = interpreter.pc
		print("[OYSComponent] 📍 Checkpoint guardado en pc=", _checkpoint_pc, " pos=", _checkpoint_snapshot.get("position", []))

# Realiza un reset completo de sistemas globales y estado del jugador
func hard_reset():
	print("[OYSComponent] Executing HARD RESET...")
	
	# 1. Detener intérprete inmediatamente
	if interpreter:
		interpreter.stop_requested = true
	
	# 2. Resetear Audio
	var am = get_node_or_null("/root/AudioManager")
	if am and am.has_method("reset"):
		am.reset()
	
	# 3. Resetear Cinemáticas
	var cm = get_node_or_null("/root/CinematicManager")
	if cm and cm.has_method("reset"):
		cm.reset()
	
	# 4. Resetear Animaciones del Jugador
	var player = _player
	if not is_instance_valid(player):
		# Intentar obtenerlo si no es válido
		# Nota: No podemos usar yield aquí porque hard_reset debe ser síncrono para el hot-reload call_deferred
		player = get_tree().get_root().find_node("Pilot", true, false)
	
	if is_instance_valid(player):
		print("[OYSComponent] Reseteando animaciones de: ", player.name)
		var anim = player.find_node("AnimationPlayer", true, false)
		if anim:
			anim.stop()
			if anim.has_animation("Idle"):
				anim.play("Idle")
		
		# Forzar reset de estados de animación si usa AnimationTree
		var tree = player.find_node("AnimationTree", true, false)
		if tree:
			tree.active = false
			tree.active = true
	
	# 5. Resetear escala de tiempo
	Engine.time_scale = 1.0
	
	# 6. Limpiar subtítulos
	var sub = get_node_or_null("/root/SubtitlesOverlayManager")
	if sub and sub.has_method("clear_all"):
		sub.clear_all()

# Limpiar estado para un nuevo script
func _clear_state():
	_player_snapshot = {}
	_initial_snapshot = {}
	_checkpoint_snapshot = {}
	_checkpoint_pc = -1
	_has_initial_position = false
	_smooth_correction_active = false
	_player = null

func on_trigger_exit():
	# Called by OYSTrigger when player exits the trigger area
	_smooth_correction_active = false
	# Optionally, stop the script/interpreter if desired:
	# interpreter.stop_requested = true
	# _set_player_pause(false)
