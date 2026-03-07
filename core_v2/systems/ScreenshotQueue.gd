extends Node

# ScreenshotQueue.gd
# Specialized Autoload for async image saving to disk.
# Prevents the game from freezing when saving a lot of screenshots (useful for OYS tests or video export).

var thread: Thread
var mutex: Mutex
var queue := []
var is_shutting_down := false

func _ready():
	name = "ScreenshotQueue"
	thread = Thread.new()
	mutex = Mutex.new()

func _exit_tree():
	is_shutting_down = true
	wait_for_empty()
	if thread.is_active():
		thread.wait_to_finish()

# Enqueues a screenshot to be saved.
func enqueue_screenshot(image: Image, path: String) -> void:
	if not image or path == "":
		printerr("[ScreenshotQueue] Invalid image or path.")
		return
		
	mutex.lock()
	queue.push_back({"image": image, "path": path})
	var start_thread = (queue.size() == 1)
	mutex.unlock()
	
	if start_thread:
		if thread.is_active():
			thread.wait_to_finish()
		thread.start(self , "_worker_function")

# Use this to freeze/wait specifically until everything is saved.
# Useful at the end of a big batch or before closing.
func wait_for_empty() -> void:
	var working = true
	while working:
		mutex.lock()
		working = queue.size() > 0
		mutex.unlock()
		if working:
			OS.delay_msec(10)
			
	if thread.is_active():
		thread.wait_to_finish()

func get_queue_size() -> int:
	mutex.lock()
	var s = queue.size()
	mutex.unlock()
	return s

func _worker_function(_userdata):
	while true:
		mutex.lock()
		if queue.empty():
			# If the queue is empty, exit thread smoothly. We will respawn it if needed.
			mutex.unlock()
			break
			
		var item = queue.front()
		mutex.unlock()
		
		var img: Image = item["image"]
		var path: String = item["path"]
		
		# Assume PropStage or whoever gave it to us already flipped it if needed, or we can just save it.
		# OYS screenshot explicitly calls flip_y() *before* saving. We'll assume the caller prepared the Image correctly.
		# However, godot-screenshot-queue flips inside the worker. Let's flip here IF we pass raw viewport data.
		# But we'll rely on the caller to flip_y if needed, since different usages might already deal with it.
		var err = img.save_png(path)
		if err != OK:
			printerr("[ScreenshotQueue] ERROR: Failed to save screenshot to: ", path, " err=", err)
			
		mutex.lock()
		queue.pop_front()
		
		# If shutting down, clear the rest
		if is_shutting_down:
			queue.clear()
		mutex.unlock()
		
		# Yield a bit of processing implicitly or explicitly
		# No explicit yield needed in OS threads, but we can do a tiny sleep to avoid starvation if we ever feel like it
		# OS.delay_msec(1)
