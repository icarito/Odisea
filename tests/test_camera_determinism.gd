class_name GdUnitTestCameraDeterminism
extends GdUnitTestSuite

# test_camera_determinism.gd
# Test de Determinismo de Cámara para Replays

const FIXED_DELTA = 1.0 / 60.0
const ReplayRecorder = preload("res://scripts/replay/ReplayRecorder.gd")
const ReplayPlayback = preload("res://scripts/replay/ReplayPlayback.gd")
const ReplayUtils = preload("res://scripts/replay/ReplayUtils.gd")
const PlayerController = preload("res://scripts/PlayerController.gd")
const PlayerSpringCam = preload("res://scripts/PlayerSpringCam.gd")

func test_camera_replay_integrity():
	# Crear CameraRig directamente
	var cam_rig = PlayerSpringCam.new()
	add_child(cam_rig)
	cam_rig.name = "CameraRig"
	
	# Crear nodos hijos mínimos
	var yaw = Spatial.new()
	yaw.name = "Yaw"
	cam_rig.add_child(yaw)
	var pitch = Spatial.new()
	pitch.name = "Pitch"
	yaw.add_child(pitch)
	
	# Llamar _ready manualmente (sin dependencias)
	cam_rig.yaw = yaw
	cam_rig.pitch = pitch
	cam_rig.target_yaw = 0.0
	cam_rig.target_pitch = 0.0
	
	# Forzar yaw/pitch
	yaw.rotation.y = 1.57  # 90 grados
	pitch.rotation.x = 0.5
	var recorded_state = cam_rig.get_replay_state()
	var recorded_yaw = recorded_state["yaw"]
	var recorded_pitch = recorded_state["pitch"]
	
	# Simular snapshot inicial
	var initial = {"camera": recorded_state}
	var state_hash = ReplayUtils.generate_state_hash(initial)
	
	# Simular playback: crear clon
	var cam_rig_clone = PlayerSpringCam.new()
	add_child(cam_rig_clone)
	cam_rig_clone.name = "CameraRigClone"
	
	var yaw_clone = Spatial.new()
	yaw_clone.name = "Yaw"
	cam_rig_clone.add_child(yaw_clone)
	var pitch_clone = Spatial.new()
	pitch_clone.name = "Pitch"
	yaw_clone.add_child(pitch_clone)
	
	cam_rig_clone.yaw = yaw_clone
	cam_rig_clone.pitch = pitch_clone
	cam_rig_clone.target_yaw = 0.0
	cam_rig_clone.target_pitch = 0.0
	
	# Aplicar estado
	cam_rig_clone.set_replay_state(recorded_state)
	cam_rig_clone.update_camera_transform()
	
	var replayed_state = cam_rig_clone.get_replay_state()
	var replayed_yaw = replayed_state["yaw"]
	var replayed_pitch = replayed_state["pitch"]
	
	# Verificar determinismo
	var yaw_diff = abs(recorded_yaw - replayed_yaw)
	var pitch_diff = abs(recorded_pitch - replayed_pitch)
	
	if yaw_diff > 0.001 or pitch_diff > 0.001:
		fail("FAIL: Replay de cámara no determinista. Yaw diff: %f, Pitch diff: %f" % [yaw_diff, pitch_diff])
	else:
		assert_that(true).is_true()  # Pass
	
	# Verificar hash
	var current_state = {"camera": replayed_state}
	var current_hash = ReplayUtils.generate_state_hash(current_state)
	assert_that(current_hash).is_equal(state_hash)
