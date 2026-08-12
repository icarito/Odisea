extends SceneTree

# bench_tick_adaptive.gd — Genera carga artificial y reporta ticks de fisica por
# frame de render. Verifica que bajo carga el juego NO entre en camara lenta:
# Engine.time_scale debe quedarse en 1.0 y el catch-up de fisica lo acota
# physics/common/max_physics_steps_per_frame.
#
# Run: godot3-bin --headless --no-window -s tools/bench_tick_adaptive.gd

func _init() -> void:
	yield(self, "idle_frame")
	print("\n[BENCH] Starting tick pressure benchmark...")

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
	var max_steps: int = int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame"))
	var peak_ticks: float = 0.0
	var min_scale: float = Engine.time_scale
	for i in range(120):
		# 45ms delay per visual frame makes the visual frames extremely slow (~22 FPS),
		# which forces Godot to try executing multiple physics ticks to catch up.
		OS.delay_msec(45)
		yield(self, "idle_frame")

		var current_avg: float = sm.get_ticks_per_frame_avg()
		peak_ticks = max(peak_ticks, current_avg)
		min_scale = min(min_scale, Engine.time_scale)
		if i % 30 == 0:
			print("[BENCH] Frame %d: ticks_per_frame_avg=%.3f, time_scale=%.3f" % [i, current_avg, Engine.time_scale])

	print("[BENCH] Peak ticks_per_frame_avg: %.3f (cap: %d)" % [peak_ticks, max_steps])
	print("[BENCH] Min time_scale observed: %.3f" % min_scale)

	if min_scale < 0.999:
		printerr("[BENCH] FAILURE: time_scale bajo a %.3f bajo carga: el juego corre en camara lenta." % min_scale)
		quit(1)
	elif peak_ticks > float(max_steps) + 0.01:
		printerr("[BENCH] FAILURE: catch-up de fisica sin acotar (%.3f ticks/frame > cap %d)." % [peak_ticks, max_steps])
		quit(1)
	else:
		print("[BENCH] SUCCESS: bajo carga el tiempo de juego sigue en tiempo real (time_scale=1.0) y el catch-up queda acotado.")
		quit(0)
