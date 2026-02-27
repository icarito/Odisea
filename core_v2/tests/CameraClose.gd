extends Spatial

# CameraClose.gd
# Helper node spawned by OYS scripts to reposition the PropStage camera
# for close-up prop validation screenshots.

func _ready():
	var cam = get_node_or_null("/root/PropStage/Camera")
	if cam:
		cam.global_transform.origin = Vector3(0, 1.2, -1.8)
		cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
		print("[CameraClose] Repositioned PropStage camera for close-up")
	else:
		printerr("[CameraClose] Could not find /root/PropStage/Camera")
