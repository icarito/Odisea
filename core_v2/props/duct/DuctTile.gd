extends Spatial

# FD-052: DuctTile.gd
# Handles player-triggered progressive collapse.

const END_CAP_PATH = "res://core_v2/props/duct/DuctEndCap.tscn"

var collapse_active := false
var triggered := false

func _ready():
	_setup_trigger()

func _setup_trigger():
	var area = Area.new()
	var col = CollisionShape.new()
	var shape = BoxShape.new()
	shape.extents = Vector3(1.5, 1.5, 0.5)
	col.shape = shape
	area.add_child(col)
	add_child(area)

	# Move trigger slightly forward to detect when player passed through
	area.translation = Vector3(0, 0, 1.0)

	area.connect("body_entered", self, "_on_player_entered")

func _on_player_entered(body):
	if triggered or not collapse_active:
		return

	if body.name == "Player" or body.is_in_group("player"):
		triggered = true
		_collapse()

func _collapse():
	# Instance EndCap to seal behind
	var cap_scene = load(END_CAP_PATH)
	if cap_scene:
		var cap = cap_scene.instance()
		add_child(cap)
		# Seal the entry point (assuming -Z is forward, we seal at +Z)
		cap.translation = Vector3(0, 0, 2.0)
		cap.rotation_degrees = Vector3(0, 180, 0)

	# Trigger FX
	_trigger_fx()

func _trigger_fx():
	# Particles
	var p = Particles.new()
	var mat = ParticlesMaterial.new()
	mat.emission_shape = ParticlesMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(2, 2, 0.1)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 45.0
	mat.gravity = Vector3(0, -9.8, 0)
	mat.initial_velocity = 2.0
	p.process_material = mat
	p.one_shot = true
	p.explosiveness = 0.8
	p.amount = 50
	p.lifetime = 2.0
	add_child(p)
	p.translation = Vector3(0, 2, 1.8)
	p.emitting = true

	# Simple cleanup
	var timer = Timer.new()
	timer.wait_time = 5.0
	timer.one_shot = true
	timer.connect("timeout", p, "queue_free")
	add_child(timer)
	timer.start()

func enable_collapse():
	collapse_active = true
