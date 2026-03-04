tool
extends RigidBody
class_name FusionCore

# FusionCore - Pushable energy cylinder with hybrid physics.
# Combines PushableBoxV2 settle logic with PropBaseV2-like activation visuals.
# When pushed, it rolls; when settled, it locks in place.
# Interacting toggles the energy state (plasma shader + light).

# --- PropBaseV2-like exports ---
export(String) var interaction_text = "Activate"
export var anim_duration = 1.0
export var starts_active = false
export var is_interactable = true

# --- Physics exports (from PushableBoxV2) ---
export var settle_threshold = 0.2
export(int) var settle_frames = 15
export var mass_value = 8.0

# --- Anim state ---
var anim_progress = 0.0
var target_progress = 0.0
var _frames_below_threshold = 0

# --- Material refs ---
var housing_mat = null
var core_mat = null

func _init():
    add_to_group("pushable")
    add_to_group("interactable")

func _ready():
    mode = RigidBody.MODE_KINEMATIC
    mass = mass_value
    contact_monitor = true
    contacts_reported = 4
    connect("body_entered", self , "_on_body_entered")
    
    if starts_active:
        anim_progress = 1.0
        target_progress = 1.0
    
    # Grab materials
    var housing = get_node_or_null("Housing")
    if housing:
        housing_mat = housing.get_surface_material(0)
        if housing_mat:
            housing_mat = housing_mat.duplicate()
            housing.set_surface_material(0, housing_mat)
    
    var core = get_node_or_null("EnergyCore")
    if core:
        core_mat = core.get_surface_material(0)
        if core_mat:
            core_mat = core_mat.duplicate()
            core.set_surface_material(0, core_mat)
    
    _update_visuals()

var _target_basis = null
var _settle_lerp_speed = 8.0

func _physics_process(delta):
    # --- Hybrid settle (from PushableBoxV2) ---
    if mode == RigidBody.MODE_RIGID:
        var vel = linear_velocity.length()
        var ang = angular_velocity.length()
        if vel < settle_threshold and ang < (settle_threshold * 2.0):
            _frames_below_threshold += 1
            if _frames_below_threshold >= settle_frames:
                _settle()
        else:
            _frames_below_threshold = 0
    elif mode == RigidBody.MODE_KINEMATIC and _target_basis != null:
        # Smooth rotation recovery
        var current_q = global_transform.basis.get_rotation_quat()
        var target_q = _target_basis.get_rotation_quat()
        if current_q.dot(target_q) > 0.9999:
            global_transform.basis = _target_basis
            _target_basis = null
        else:
            var next_q = current_q.slerp(target_q, _settle_lerp_speed * delta)
            global_transform.basis = Basis(next_q)
    
    # --- Anim progress (from PropBaseV2) ---
    if abs(anim_progress - target_progress) > 0.001:
        var speed = 1.0 / max(anim_duration, 0.01)
        if anim_progress < target_progress:
            anim_progress = min(anim_progress + speed * delta, target_progress)
        else:
            anim_progress = max(anim_progress - speed * delta, target_progress)
        _update_visuals()

func _settle():
    global_transform.origin = _round_vec3(global_transform.origin, 4)
    mode = RigidBody.MODE_KINEMATIC
    linear_velocity = Vector3.ZERO
    angular_velocity = Vector3.ZERO
    _frames_below_threshold = 0
    
    # Auto-upright when active (energy stabilizer)
    if anim_progress > 0.3:
        var euler = global_transform.basis.get_euler()
        euler.x = 0.0
        euler.z = 0.0
        _target_basis = Basis(euler)

func wake_up():
    if mode == RigidBody.MODE_KINEMATIC:
        mode = RigidBody.MODE_RIGID
        sleeping = false
        _frames_below_threshold = 0

func _on_body_entered(_body):
    if mode == RigidBody.MODE_KINEMATIC:
        wake_up()

func interact():
    target_progress = 0.0 if target_progress > 0.5 else 1.0

var is_active = false
var _auto_triggered = false

func set_active(val, _instant = false):
    is_active = val
    target_progress = 1.0 if val else 0.0

func set_highlighted(_val, _color = null):
    pass

func set_proximity_highlight(_val, _color = null):
    pass

func _update_visuals():
    # Housing glow lines
    if housing_mat and housing_mat is ShaderMaterial:
        housing_mat.set_shader_param("charge_level", anim_progress)
    
    # Energy sphere plasma
    if core_mat and core_mat is ShaderMaterial:
        core_mat.set_shader_param("charge_level", anim_progress)
    
    # Core light
    var light = get_node_or_null("CoreLight")
    if light:
        light.light_energy = anim_progress * 4.0
    
    # Energy particles
    var particles = get_node_or_null("EnergyParticles")
    if particles:
        particles.emitting = anim_progress > 0.1
        particles.speed_scale = 0.3 + 2.0 * anim_progress

func _round_vec3(p_vec, p_decimals):
    var m = pow(10, p_decimals)
    return Vector3(round(p_vec.x * m) / m, round(p_vec.y * m) / m, round(p_vec.z * m) / m)

# --- Replay/snapshot support ---
func get_snapshot():
    var rot = global_transform.basis.get_euler()
    return {
        "pos": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
        "rot": [rot.x, rot.y, rot.z],
        "vel": [linear_velocity.x, linear_velocity.y, linear_velocity.z],
        "mode": mode,
        "progress": anim_progress,
        "target": target_progress
    }

func restore_snapshot(data):
    if data.has("mode"):
        mode = data["mode"]
    if data.has("pos"):
        var p = data["pos"]
        global_transform.origin = Vector3(p[0], p[1], p[2])
    if data.has("rot"):
        var r = data["rot"]
        global_transform.basis = Basis(Vector3(r[0], r[1], r[2]))
    if data.has("vel"):
        var v = data["vel"]
        linear_velocity = Vector3(v[0], v[1], v[2])
    if data.has("progress"):
        anim_progress = data["progress"]
    if data.has("target"):
        target_progress = data["target"]
    _update_visuals()
