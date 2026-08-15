extends Spatial

# AtmoStation.gd — traduce el ciclo determinista de PressureSection a una
# esclusa legible: manómetro blanco/rojo, baliza y chispa antes del blowout.
# PipeValve funciona como el mando físico del PurgeDial: abrirla alinea el
# dial y sostenerlo en la zona estable purga la sección.

const PRESSURE_NOMINAL := 0
const PRESSURE_RISING := 1
const PRESSURE_CRITICAL := 2

const GAUGE_MIN_ANGLE := -2.15
const GAUGE_MAX_ANGLE := 2.15
const PANEL_STABLE := Color(0.72, 0.9, 0.96, 1.0)
const PANEL_WARNING := Color(1.0, 0.05, 0.03, 1.0)
const PANEL_PURGED := Color(0.12, 0.9, 0.42, 1.0)

onready var _section: Node = get_node_or_null("PressureSection")
onready var _dial: Node = get_node_or_null("PurgeDial")
onready var _purge_valve: Node = get_node_or_null("PurgeValve")
onready var _needle: Spatial = get_node_or_null("Gauge/GaugePivot")
onready var _panel: MeshInstance = get_node_or_null("PressurePanel")
onready var _alarm_strip: MeshInstance = get_node_or_null("AlarmStrip")
onready var _spark: MeshInstance = get_node_or_null("Spark")
onready var _beacon: Node = get_node_or_null("EmergencyBeacon")

var _panel_material: SpatialMaterial = null
var _spark_material: SpatialMaterial = null
var _visual_phase: float = 0.0


func _ready() -> void:
	if _purge_valve and _purge_valve.has_signal("valve_state_changed"):
		_purge_valve.connect("valve_state_changed", self, "_on_purge_valve_changed")
	if _panel:
		_panel_material = _panel.get_surface_material(0) as SpatialMaterial
	if _alarm_strip:
		_alarm_strip.set_surface_material(0, _panel_material)
	if _spark:
		_spark_material = _spark.get_surface_material(0) as SpatialMaterial
	_apply()


func _physics_process(delta: float) -> void:
	_visual_phase = fmod(_visual_phase + delta, 1.0)
	_apply()


func _on_purge_valve_changed(is_open: bool) -> void:
	if not _dial:
		return
	if is_open:
		_dial.value = _dial.target
	else:
		_dial.value = 0.0


func _apply() -> void:
	if not _section:
		return
	var pressure: float = _section.get_pressure()
	var state: int = _section.get_state()
	var normalized: float = clamp((pressure - 1.0) / max(_section.critical_pressure - 1.0, 0.01), 0.0, 1.0)

	if _needle:
		_needle.rotation.z = lerp(GAUGE_MIN_ANGLE, GAUGE_MAX_ANGLE, normalized)

	var alarm_active: bool = state == PRESSURE_RISING or state == PRESSURE_CRITICAL
	var critical: bool = state == PRESSURE_CRITICAL
	if _panel_material:
		_panel_material.emission_enabled = true
		if state == PRESSURE_NOMINAL:
			_panel_material.emission = PANEL_STABLE
			_panel_material.emission_energy = 0.45
		elif alarm_active:
			var flicker: bool = _visual_phase < 0.55
			_panel_material.emission = PANEL_WARNING
			_panel_material.emission_energy = 2.3 if flicker else 0.12
		else:
			_panel_material.emission = PANEL_PURGED
			_panel_material.emission_energy = 1.4

	if _spark_material:
		_spark_material.emission_enabled = true
		_spark_material.emission = PANEL_WARNING
		_spark_material.emission_energy = 5.0 if critical and _visual_phase < 0.2 else 0.0

	if _beacon and _beacon.has_method("set_active"):
		_beacon.set_active(alarm_active)


func interact() -> void:
	# Puente para OYS: el jugador real interactúa con PipeValve; el harness de
	# prop opera la raíz de estación y necesita recorrer el mismo camino.
	if _purge_valve and _purge_valve.has_method("interact"):
		_purge_valve.interact()
