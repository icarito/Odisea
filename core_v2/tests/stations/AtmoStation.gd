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
onready var _pipes: Node = get_node_or_null("Pipes")
onready var _dial_pivot: Spatial = get_node_or_null("Gauge/DialPivot")
onready var _dial_needle: MeshInstance = get_node_or_null("Gauge/DialPivot/DialNeedle")
onready var _target_band: MeshInstance = get_node_or_null("Gauge/TargetBand")

# Cuánto avanza el dial por cada giro de válvula. Con 0.17 hacen falta ~4 giros para
# cruzar la zona verde: suficiente para que se sienta que uno está buscando el punto,
# y poco como para no aburrir.
const DIAL_STEP := 0.17
# Las fugas de vapor arrancan escalonadas: cuanto más sube la presión, más juntas ceden.
onready var _steam := [get_node_or_null("SteamA"), get_node_or_null("SteamB"), get_node_or_null("SteamC")]

# Caudal de la conducción: en reposo corre lento; con sobrepresión se acelera.
const PIPE_SPEED_NOMINAL := 0.35
const PIPE_SPEED_CRITICAL := 1.8
const PIPE_FLOW_NOMINAL := 0.6
const PIPE_FLOW_CRITICAL := 1.5

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


func _on_purge_valve_changed(_is_open: bool) -> void:
	# Cada giro de la válvula avanza el dial un paso y vuelve a empezar al pasarse: es
	# un mando de sintonía, no un interruptor. Antes la válvula saltaba directo al valor
	# exacto, así que el mini-juego de buscar la zona verde no existía: se abría y a los
	# 1.2 s purgaba sin que se viera nada en el medio.
	if not _dial or not _dial.has_method("nudge"):
		return
	var next_value: float = _dial.value + DIAL_STEP
	if next_value > 1.0:
		next_value -= 1.0
	_dial.nudge(next_value - _dial.value)


func _apply() -> void:
	if not _section:
		return
	var pressure: float = _section.get_pressure()
	var state: int = _section.get_state()
	var normalized: float = clamp((pressure - 1.0) / max(_section.critical_pressure - 1.0, 0.01), 0.0, 1.0)

	if _needle:
		_needle.rotation.z = lerp(GAUGE_MIN_ANGLE, GAUGE_MAX_ANGLE, normalized)

	# La aguja de ajuste es la que el jugador mueve. Vive en el mismo manómetro que la
	# de presión para que se lea de un vistazo qué hay que alinear con qué.
	if _dial and _dial_pivot:
		_dial_pivot.rotation.z = lerp(GAUGE_MIN_ANGLE, GAUGE_MAX_ANGLE, clamp(_dial.value, 0.0, 1.0))
	if _dial and _target_band:
		_target_band.rotation.z = lerp(GAUGE_MIN_ANGLE, GAUGE_MAX_ANGLE, clamp(_dial.target, 0.0, 1.0))
	# Feedback sensorial que pide el FD: la zona verde y la aguja se encienden al
	# acercarse, y quedan fijas al enganchar. Es lo único que dice "vas bien".
	if _dial and _dial.has_method("get_proximity"):
		var proximity: float = _dial.get_proximity()
		var locked: bool = _dial.has_method("is_locked") and _dial.is_locked()
		var glow: float = 0.6 + 3.4 * proximity
		if _target_band and _target_band.get_surface_material(0):
			_target_band.get_surface_material(0).emission_energy = 4.5 if locked else glow
		if _dial_needle and _dial_needle.get_surface_material(0):
			_dial_needle.get_surface_material(0).emission_energy = 4.5 if locked else glow

	# La cañería acusa la presión antes que cualquier cartel: el aire corre más rápido y
	# empiezan a ceder las juntas, una a una, de menor a mayor presión.
	if _pipes and _pipes.has_method("set_flow_speed"):
		_pipes.set_flow_speed(lerp(PIPE_SPEED_NOMINAL, PIPE_SPEED_CRITICAL, normalized))
		_pipes.set_flow_intensity(lerp(PIPE_FLOW_NOMINAL, PIPE_FLOW_CRITICAL, normalized))
	for i in range(_steam.size()):
		var jet = _steam[i]
		if jet == null or not jet.has_method("set_active"):
			continue
		var threshold: float = 0.25 + 0.25 * float(i)
		var should_leak: bool = normalized > threshold
		if jet.is_active != should_leak:
			jet.set_active(should_leak)

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
