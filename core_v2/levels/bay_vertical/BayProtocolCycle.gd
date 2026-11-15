extends Node
class_name BayProtocolCycle

# Ciclo de protocolo GLOBAL de la bahía vertical radial (FD-322).
#
# Generalización del ciclo de protocolo de `LabyrinthSection.gd` (FD-320+): en vez
# de alternar fuego/gas con fases propias, este nodo es un reloj determinista de
# fases calma/aviso/peligro que cualquier peligro o luminaria de la sala consulta.
# Toda la sala se sincroniza contra el mismo reloj: las luces pintan la fase y cada
# peligro abre su ventana local dentro de DANGER.
#
# Determinismo: la fase deriva de la acumulación de `_elapsed` en `_physics_process`
# (nada de RNG). Miembro de `replay_sync` con `get_snapshot`/`restore_snapshot`.

enum Phase { SAFE = 0, WARNING = 1, DANGER = 2 }

signal phase_changed(new_phase)

export(float) var safe_duration := 6.0
export(float) var warning_duration := 2.5
export(float) var danger_duration := 5.0

var _elapsed := 0.0
var _phase: int = Phase.SAFE

func _init() -> void:
	add_to_group("replay_sync")

func _physics_process(delta: float) -> void:
	_elapsed += delta
	var new_phase: int = phase_for_time(_elapsed)
	if new_phase != _phase:
		_phase = new_phase
		emit_signal("phase_changed", _phase)

func phase_for_time(t: float) -> int:
	var cycle: float = safe_duration + warning_duration + danger_duration
	var tt: float = fmod(t, cycle)
	if tt < safe_duration:
		return Phase.SAFE
	if tt < safe_duration + warning_duration:
		return Phase.WARNING
	return Phase.DANGER

func get_phase() -> int:
	return _phase

func get_elapsed() -> float:
	return _elapsed

# ── Estado serializable (replay + save) ───────────────────────────────────────

func get_snapshot() -> Dictionary:
	return {
		"elapsed": _elapsed,
		"phase": _phase,
	}

func restore_snapshot(data: Dictionary) -> void:
	_elapsed = float(data.get("elapsed", 0.0))
	_phase = int(data.get("phase", int(Phase.SAFE)))
