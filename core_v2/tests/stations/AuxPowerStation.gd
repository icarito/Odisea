extends Spatial

# AuxPowerStation.gd — cablea la lectura OD-02 y la puerta sellada con el estado
# del respaldo eléctrico (FD-259).
#
# No tiene estado propio: todo sale de AuxPowerBus (core_v2/systems/auxpower/,
# todavía no existe — llega por otra tarea en paralelo). Este nodo se engancha
# por duck typing, nunca por class_name, así que funciona igual de bien si el
# bus no está: la estación arranca "sin energía" (puerta sellada, OD-02
# parpadeando con un contador propio), que es justamente el estado que hay que
# poder leer sin texto (FD-259 §3).

onready var _bus: Node = get_node_or_null("AuxPowerBus")
onready var _door_slide: Node = get_node_or_null("Door/Mechanism")
onready var _panel: MeshInstance = get_node_or_null("OD02Panel")
onready var _lever: Node = get_node_or_null("LeverV2")
onready var _source: Node = get_node_or_null("PowerSource")

# Hasta que exista AuxPowerBus, el sector se considera alimentado para poder probar el
# circuito de punta a punta (bajar la palanca abre la puerta). Cuando el bus aterrice,
# él manda: cortar la energía deja la palanca sin efecto, que es la regla del FD-259.
export(bool) var assume_powered_without_bus := true
# El lever le pide energía al bus: es la secuencia de restauración del FD-259.
export(bool) var lever_requests_restore := true

# Lectura OD-02: mismo verde de sistema que documenta FD-255.
const OD02_ALBEDO := Color(0.15, 0.7, 0.3)
const OD02_EMISSION := Color(0.03, 0.3, 0.1)
const OD02_ENERGY_LIT := 1.6
const OD02_ENERGY_OFF := 0.05
const OD02_ENERGY_STABLE := 2.0

# Parpadeo de aviso cuando no hay bus: ritmo legible, no estroboscópico.
const FALLBACK_FLICKER_PERIOD := 1.6
const FALLBACK_FLICKER_ON_RATIO := 0.6

var _panel_material: SpatialMaterial = null
var _fallback_phase := 0.0
var _door_open := false


func _ready() -> void:
	if lever_requests_restore and _lever and _bus and _lever.has_signal("lever_toggled"):
		_lever.connect("lever_toggled", self, "_on_lever_toggled")
	if _panel:
		_panel_material = _panel.get_surface_material(0)
		if _panel_material == null:
			_panel_material = SpatialMaterial.new()
			_panel.set_surface_material(0, _panel_material)
		_panel_material.albedo_color = OD02_ALBEDO
		_panel_material.emission_enabled = true

	_apply(false, 0.0)


func _physics_process(delta: float) -> void:
	var powered := assume_powered_without_bus
	if _bus and _bus.has_method("is_powered"):
		powered = _bus.is_powered()

	var phase := 0.0
	if not powered:
		if _bus and _bus.has_method("get_flicker_phase"):
			phase = _bus.get_flicker_phase()
		else:
			# Sin bus (o sin ese método): contador propio, determinista, nunca
			# randf()/get_ticks_msec() (AGENTS.md §5.3).
			_fallback_phase = fmod(_fallback_phase + delta, FALLBACK_FLICKER_PERIOD)
			phase = _fallback_phase / FALLBACK_FLICKER_PERIOD

	_apply(powered, phase)


func _apply(powered: bool, phase: float) -> void:
	if _panel_material:
		if powered:
			_panel_material.emission = OD02_EMISSION
			_panel_material.emission_energy = OD02_ENERGY_STABLE
		else:
			var lit: bool = phase < FALLBACK_FLICKER_ON_RATIO
			_panel_material.emission = OD02_EMISSION
			_panel_material.emission_energy = OD02_ENERGY_LIT if lit else OD02_ENERGY_OFF

	# La puerta NO se maneja desde acá: la abre el circuito (fuente AND palanca -> puerta).
	# Esta estación solo alimenta la fuente; si la energía y la palanca no coinciden, la
	# puerta se queda sellada, y eso es exactamente lo que tiene que leerse.
	if _source and _source.has_method("set_active") and powered != _door_open:
		_door_open = powered
		_source.set_active(powered)


func _on_lever_toggled(is_on: bool) -> void:
	# Bajar la palanca pide el arranque del respaldo; subirla lo corta. La puerta no la
	# abre esto: la abre el circuito cuando coinciden energía y palanca.
	if not _bus:
		return
	if is_on and _bus.has_method("request_restore"):
		_bus.request_restore()
	elif not is_on and _bus.has_method("cut_power"):
		_bus.cut_power()


func interact() -> void:
	# Puente para el harness OYS (test_prop.sh / prop_validator.oys), igual que
	# CircuitTestScene.gd: reenvía al lever para que su animación se vea en las
	# capturas. No es estado de gameplay — el lever ya administra el suyo, y quien
	# escucha su señal es el LogicCircuitManager del nodo Circuit.
	if _lever and _lever.has_method("interact"):
		_lever.interact()
