extends SceneTree

# bench_tick_adaptive.gd — Genera carga artificial, reporta ticks/frame y time_scale resultante.
#
# Run: godot3-bin --headless --no-window -s tools/bench_tick_adaptive.gd

func _init() -> void:
	yield(self, "idle_frame")
	print("\n[BENCH] Starting tick adaptive benchmark...")

	# Make sure SessionManager exists
	var sm = get_root().get_node_or_null("SessionManager")
	if sm == null:
		printerr("[BENCH] SessionManager autoload not found.")
		quit(1)
		return

	# Run for some frames to establish a baseline
	print("[BENCH] Running baseline...")
	for _i in range(30):
		yield(self, "idle_frame")

	var baseline_avg: float = sm.get_ticks_per_frame_avg()
	print("[BENCH] Baseline ticks_per_frame_avg: ", baseline_avg)
	print("[BENCH] Baseline time_scale: ", Engine.time_scale)

	# Simulate slow device by adding artificial delay in main thread
	print("[BENCH] Simulating heavy physics load (introducing 45ms frame delays)...")
	var success: bool = false
	for i in range(120):
		# 45ms delay per visual frame makes the visual frames extremely slow (~22 FPS),
		# which forces Godot to try executing multiple physics ticks to catch up.
		OS.delay_msec(45)
		yield(self, "idle_frame")

		var current_avg: float = sm.get_ticks_per_frame_avg()
		var current_scale: float = Engine.time_scale
		if i % 30 == 0:
			print("[BENCH] Frame %d: ticks_per_frame_avg=%.3f, time_scale=%.3f" % [i, current_avg, current_scale])

		# If time_scale gets reduced below 1.0, we have successfully triggered adaptive time scaling!
		if current_scale < 1.0:
			success = true

	var final_avg: float = sm.get_ticks_per_frame_avg()
	var final_scale: float = Engine.time_scale
	print("[BENCH] Final ticks_per_frame_avg: ", final_avg)
	print("[BENCH] Final time_scale: ", final_scale)

	if success and final_scale < 0.99:
		print("[BENCH] SUCCESS: Adaptive time scaling successfully reduced time_scale (to %.3f) to mitigate simulated load." % final_scale)
		quit(0)
	else:
		printerr("[BENCH] FAILURE: time_scale did not decrease under load (final time_scale: %.3f)." % final_scale)
		quit(1)
