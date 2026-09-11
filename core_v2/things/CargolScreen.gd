extends HUDableComponent
class_name CargolScreen

# CargolScreen.gd - HUDable screen source for Cargol defensive drone (FD-296 F2)

const WidgetScene = preload("res://core_v2/ui/hud/CargolWidget.tscn")

export(NodePath) var cargol_path: NodePath = NodePath("")

func _init() -> void:
	hud_screen_id = "drone:cargol"
	hud_screen_title = "Cargol"
	hud_widget_scene = WidgetScene
	default_relevance = 0.1

func _ready() -> void:
	pass

func widget_snapshot() -> Dictionary:
	var drone = _get_drone()
	var state_val := 0
	var cooldown_val := 0.0
	var notif_val := ""

	if is_instance_valid(drone):
		if "state" in drone:
			state_val = int(drone.state)
		if "cooldown_timer" in drone:
			cooldown_val = float(drone.cooldown_timer)

		var notif_lbl = drone.get_node_or_null("NotificationLabel")
		if is_instance_valid(notif_lbl) and "text" in notif_lbl:
			notif_val = String(notif_lbl.text)

	return {
		"proto": 1,
		"id": screen_id(),
		"title": screen_title(),
		"drone_state": state_val,
		"cooldown": cooldown_val,
		"notification": notif_val,
		"source": "online"
	}

func relevance(context: Dictionary = {}) -> float:
	var rel: float = default_relevance
	var drone = _get_drone()

	if is_instance_valid(drone):
		var st: int = int(drone.state) if "state" in drone else 0
		if st == 1 or st == 2 or st == 4 or st == 5:
			rel += 0.5

		if context.has("player_position") and typeof(context["player_position"]) == TYPE_ARRAY and context["player_position"].size() >= 3:
			if drone is Spatial:
				var p_pos := Vector3(float(context["player_position"][0]), float(context["player_position"][1]), float(context["player_position"][2]))
				var d_pos: Vector3 = (drone as Spatial).global_transform.origin
				if d_pos.distance_to(p_pos) < 15.0:
					rel += 0.3

	return clamp(rel, 0.0, 1.0)

func _get_drone() -> Node:
	if not String(cargol_path).empty():
		var n = get_node_or_null(cargol_path)
		if is_instance_valid(n):
			return n

	if is_inside_tree():
		var nodes = get_tree().get_nodes_in_group("cargol_defensive")
		if not nodes.empty():
			return nodes[0]

	return null
