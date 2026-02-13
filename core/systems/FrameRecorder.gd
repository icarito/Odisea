extends Node

# FrameRecorder.gd - Tool for exporting frames for high-quality trailers

export(bool) var export_on_start := false
export(int) var target_fps := 60
export(String) var output_folder := "res://render/"

var is_recording := false
var frame_count := 0

func _ready():
	if export_on_start:
		start_recording()

func start_recording():
	if is_recording: return

	print("[FrameRecorder] Starting recording to: ", output_folder)

	# Ensure directory exists
	var dir = Directory.new()
	if not dir.dir_exists(output_folder):
		dir.make_dir_recursive(output_folder)

	# --- ENGINE LOCKING (as per spec) ---
	# To avoid jumps during heavy disk I/O, we lock the iterations.
	Engine.target_fps = target_fps
	Engine.iterations_per_second = target_fps

	is_recording = true
	frame_count = 0

func stop_recording():
	if not is_recording: return

	print("[FrameRecorder] Stopping recording. Total frames: ", frame_count)
	is_recording = false
	Engine.target_fps = 0 # Unlock
	Engine.iterations_per_second = 60 # Default

func _process(_delta):
	if is_recording:
		# Use call_deferred to ensure we are at the end of the frame
		# or just do it here if we assume _process is called after draw calls are queued.
		# In Godot 3, capturing the viewport texture in _process usually gives the PREVIOUS frame
		# unless we wait for idle_frame.
		_capture_sequence()

var _is_capturing := false
func _capture_sequence():
	if _is_capturing: return
	_is_capturing = true

	# Wait until the end of the current frame to ensure everything is rendered
	yield(get_tree(), "idle_frame")

	var img = get_viewport().get_texture().get_data()
	img.flip_y()

	var filename = output_folder + "frame_" + str(frame_count).pad_zeros(6) + ".png"
	# NOTE: save_png is synchronous and will block the main thread.
	# This is desired here to "block motor time" and ensure no frame is skipped.
	img.save_png(filename)

	frame_count += 1

	# Debug print every 60 frames
	if frame_count % 60 == 0:
		print("[FrameRecorder] Captured frame ", frame_count)

	_is_capturing = false
