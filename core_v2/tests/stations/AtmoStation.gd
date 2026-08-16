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
onready var _tuner: Node = get_node_or_null("PurgeTuner")
onready var _gauge_ui: Control = get_node_or_null("Gauge/Viewport/PressureGaugeUI")
onready var _gauge_screen: MeshInstance = get_node_or_null("Gauge/ScreenMesh")
onready var _gauge_viewport: Viewport = get_node_or_null("Gauge/Viewport")
onready var _panel: MeshInstance = get_node_or_null("PressurePanel")
onready var _alarm_strip: MeshInstance = get_node_or_null("AlarmStrip")
onready var _spark: Node = get_node_or_null("Spark")
onready var _beacon: Node = get_node_or_null("EmergencyBeacon")
onready var _pipes: Node = get_node_or_null("Pipes")
onready var _pump: Node = get_node_or_null("PressurePump")

# Cuánto avanza el dial por cada giro de válvula. Con 0.17 hacen falta ~4 giros para
# cruzar la zona verde: suficiente para que se sienta que uno está buscando el punto,
# y poco como para no aburrir.
const DIAL_STEP := 0.17
# Las fugas de vapor arrancan escalonadas: cuanto más sube la presión, más juntas ceden.
onready var _steam := [get_node_or_null("SteamA"), get_node_or_null("SteamB"), get_node_or_null("SteamC"),
	get_node_or_null("SteamD"), get_node_or_null("SteamE"), get_node_or_null("SteamF")]

# Caudal de la conducción: en reposo corre lento; con sobrepresión se acelera.
const PIPE_SPEED_NOMINAL := 0.35
const PIPE_SPEED_CRITICAL := 1.8
const PIPE_FLOW_NOMINAL := 0.6
const PIPE_FLOW_CRITICAL := 1.5

var _panel_material: SpatialMaterial = null
var _visual_phase: float = 0.0


func _ready() -> void:
	# La pantalla toma su textura del Viewport hermano. Se conecta acá y no en la escena
	# porque un ViewportTexture guardado en .tscn se rompe al reparentar la estación.
	if _gauge_screen and _gauge_viewport:
		var mat = _gauge_screen.get_surface_material(0)
		if mat is ShaderMaterial:
			mat.set_shader_param("texture_albedo", _gauge_viewport.get_texture())
	if _pump and _pump.has_signal("hold_started"):
		_pump.connect("hold_started", self, "_on_pump_hold_started")
	if _panel:
		_panel_material = _panel.get_surface_material(0) as SpatialMaterial
	if _alarm_strip:
		_alarm_strip.set_surface_material(0, _panel_material)
	_apply()


func _physics_process(delta: float) -> void:
	_visual_phase = fmod(_visual_phase + delta, 1.0)
	# Bombear inyecta presión mientras dure el esfuerzo: la aguja trepa mientras se
	# sostiene y se queda quieta al soltar. Antes la bomba solo daba el pistoletazo de
	# salida y la presión subía sola, así que el mando y el manómetro no se relacionaban.
	if _pump and _section and _pump.has_method("is_held") and _pump.is_held():
		if _section.has_method("inject"):
			_section.inject(delta)
	_apply()


func _on_pump_hold_started() -> void:
	# El primer golpe de bomba saca al sector del reposo; el resto de la subida la hace
	# el bombeo sostenido en _physics_process.
	if _section and _section.has_method("raise_pressure"):
		_section.raise_pressure()


func _apply() -> void:
	if not _section:
		return
	var pressure: float = _section.get_pressure()
	var state: int = _section.get_state()
	var normalized: float = clamp((pressure - 1.0) / max(_section.critical_pressure - 1.0, 0.01), 0.0, 1.0)

	if _gauge_ui and _gauge_ui.has_method("set_state"):
		var dial_value: float = _dial.value if _dial else 0.0
		var dial_target: float = _dial.target if _dial else 0.62
		var dial_tol: float = _dial.tolerance if _dial else 0.08
		var prox: float = _dial.get_proximity() if _dial and _dial.has_method("get_proximity") else 0.0
		var is_locked: bool = _dial.is_locked() if _dial and _dial.has_method("is_locked") else false
		var rising: bool = state == PRESSURE_RISING or state == PRESSURE_CRITICAL
		_gauge_ui.set_state(normalized, dial_value, dial_target, dial_tol, prox, is_locked, rising)

	# La cañería acusa la presión antes que cualquier cartel: el aire corre más rápido y
	# empiezan a ceder las juntas, una a una, de menor a mayor presión.
	if _pipes and _pipes.has_method("set_flow_speed"):
		_pipes.set_flow_speed(lerp(PIPE_SPEED_NOMINAL, PIPE_SPEED_CRITICAL, normalized))
		_pipes.set_flow_intensity(lerp(PIPE_FLOW_NOMINAL, PIPE_FLOW_CRITICAL, normalized))
	for i in range(_steam.size()):
		var jet = _steam[i]
		if jet == null or not jet.has_method("set_active"):
			continue
		# Escalonadas a lo largo de toda la escala: la primera junta cede casi enseguida y
		# la última recién al borde del estallido, así la presión se lee en cuántas pierden.
		var threshold: float = 0.12 + 0.13 * float(i)
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

	# El arco eléctrico solo existe en CRITICAL: es el último aviso antes del estallido.
	if _spark and _spark.has_method("set_active"):
		_spark.set_active(critical)
	elif _spark and _spark is Spatial:
		_spark.visible = critical

	if _beacon and _beacon.has_method("set_active"):
		_beacon.set_active(alarm_active)


func interact() -> void:
	# Puente para OYS: el jugador real sostiene el mando de sintonía; el harness opera la
	# raíz de la estación, así que acá se le da un pulso de barrido para que las capturas
	# muestren algo moviéndose.
	if _tuner and _tuner.has_method("set_held"):
		_tuner.set_held(not _tuner.is_held())
