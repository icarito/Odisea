extends KinematicBody

# MultiToolGlooProjectile.gd
# Projectile that flies with gravity and sticks to static surfaces.

export(float) var gravity := 9.8
export(float) var speed := 15.0
export(float) var lifetime := 60.0 # Long lifetime, but MultiToolV2 manages the count

var velocity := Vector3.ZERO
var _is_stuck := false
var _age := 0.0

onready var _mesh: MeshInstance = $MeshInstance
onready var _particles: CPUParticles = $ImpactParticles
onready var _collision_shape: CollisionShape = $CollisionShape

func _ready():
	set_as_toplevel(true)
	add_to_group("replay_sync")

func launch(start_transform: Transform):
	global_transform = start_transform
	velocity = -start_transform.basis.z * speed
	set_physics_process(true)

func _physics_process(delta):
	# Normal physics process only if not managed by a session (replay/recording)
	var sm = get_node_or_null("/root/SessionManager")
	if sm and (sm.is_recording or sm.is_replaying):
		return
	step(delta)

func step(delta: float):
	if _is_stuck:
		_age += delta
		if _age > lifetime:
			fade_out()
		return

	velocity.y -= gravity * delta
	
	var collision = move_and_collide(velocity * delta)
	if collision:
		_handle_collision(collision)

func get_snapshot() -> Dictionary:
	return {
		"p": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
		"v": [velocity.x, velocity.y, velocity.z],
		"s": _is_stuck,
		"a": _age
	}

func restore_snapshot(data: Dictionary):
	if data.has("p"):
		var p = data["p"]
		global_transform.origin = Vector3(p[0], p[1], p[2])
	if data.has("v"):
		var v = data["v"]
		velocity = Vector3(v[0], v[1], v[2])
	if data.has("s"):
		_is_stuck = data["s"]
	if data.has("a"):
		_age = data["a"]

func _handle_collision(collision: KinematicCollision):
	var collider = collision.collider
	if collider is StaticBody or collider is CSGShape:
		_stick(collision)
	else:
		# Simple bounce for other things (e.g. physics props)
		velocity = velocity.bounce(collision.normal) * 0.5

func _stick(collision: KinematicCollision):
	_is_stuck = true
	velocity = Vector3.ZERO
	
	# Small adjustment to visual position to sit ON the surface
	global_transform.origin = collision.position + collision.normal * 0.05
	
	# Visual feedback
	if _particles:
		_particles.emitting = true
	
	# Change collision layer to avoid hitting player?
	# Or keep it to allow player to stand on it (if large enough)?
	# For now, just stop.
	
	# Reparent to collider if it's moving? (Beyond current scope, sticking to StaticBody)
	if collision.collider is Spatial:
		var parent = collision.collider
		var old_transform = global_transform
		get_parent().remove_child(self)
		parent.add_child(self)
		global_transform = old_transform

func fade_out():
	# Simple shrink and free
	var tween = create_tween()
	if tween:
		tween.tween_property(self, "scale", Vector3.ZERO, 0.5)
		tween.tween_callback(self, "queue_free")
	else:
		# Fallback if tweening not available/working as expected in GLES2/3.6
		queue_free()

func create_tween() -> SceneTreeTween:
	if get_tree():
		return get_tree().create_tween()
	return null
