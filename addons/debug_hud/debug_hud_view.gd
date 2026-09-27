extends ImGuiCanvas

# debug_hud_view.gd - Vista ImGui del DebugHud: widget mini siempre visible + HUD
# completo (F1) con pestanas Graficas y Monitores. Port acotado de
# gdtk/addons/debug_hud/debug_hud.gd (SPEC-hud.md, SPEC-hud-remote.md).
#
# Deliberadamente SIN pestana de consola / linea de comandos: Odisea ya tiene una
# consola de debug diegetica completa (OYS_Console.gd, tecla ` -> DebugConsoleHUD,
# fps/timescale/etc no existen ahi pero cvars/set/get cubren ese rol) y AGENTS.md 1.2
# pide no duplicar sistemas existentes. Este overlay es solo de metricas de motor
# (FPS, frame ms, draw calls, memoria, GPU si el fork trae FRT_PERF).
#
# NO tiene class_name (ver debug_hud.gd): un binario sin el modulo imgui no puede
# compilar `extends ImGuiCanvas`. Solo se instancia con load() diferido y detras de
# ClassDB.class_exists("ImGuiCanvas") (debug_hud.gd._build_view). No preload() aca.
#
# Tecla: F1. NO backtick (QUOTELEFT): esa tecla ya es "toggle_debug_console" en el
# input map de Odisea (project.godot) y el fork la comparte con este HUD; con las dos
# vivas, un toque abriria/cerraria ambas consolas a la vez.

var hud = null # DebugHud (autoload), inyectado por debug_hud.gd._build_view()

var mini_corner := 3
# ImGuiCanvas (Node2D) ya trae una propiedad "scale": nombre distinto para no chocar
# (medido: "Parse Error: The member "scale" already exists in a parent class.").
var mini_scale := 1.0
var has_implot := false

var GROUPS := [
	["Frame", ["TIME_FPS", "TIME_PROCESS", "TIME_PHYSICS_PROCESS"]],
	["Render", ["RENDER_DRAW_CALLS_IN_FRAME", "RENDER_2D_DRAW_CALLS_IN_FRAME",
		"RENDER_OBJECTS_IN_FRAME", "RENDER_VERTICES_IN_FRAME",
		"RENDER_MATERIAL_CHANGES_IN_FRAME", "RENDER_SHADER_CHANGES_IN_FRAME",
		"RENDER_SURFACE_CHANGES_IN_FRAME", "RENDER_2D_ITEMS_IN_FRAME"]],
	["Memoria", ["MEMORY_STATIC", "MEMORY_DYNAMIC", "MEMORY_STATIC_MAX",
		"RENDER_VIDEO_MEM_USED", "RENDER_TEXTURE_MEM_USED", "RENDER_VERTEX_MEM_USED"]],
	["Objetos", ["OBJECT_COUNT", "OBJECT_RESOURCE_COUNT", "OBJECT_NODE_COUNT",
		"OBJECT_ORPHAN_NODE_COUNT"]],
	["Fisica", ["PHYSICS_3D_ACTIVE_OBJECTS", "PHYSICS_3D_COLLISION_PAIRS",
		"PHYSICS_3D_ISLAND_COUNT"]],
	["Audio", ["AUDIO_OUTPUT_LATENCY"]],
	["GPU", ["gpu", "frt_frame", "frt_render", "frt_sync", "frt_other"]],
]

var UNITS := {
	"TIME_PROCESS": "ms", "TIME_PHYSICS_PROCESS": "ms", "collector_us": "us",
	"MEMORY_STATIC": "MB", "MEMORY_DYNAMIC": "MB", "MEMORY_STATIC_MAX": "MB",
	"MEMORY_DYNAMIC_MAX": "MB", "MEMORY_MESSAGE_BUFFER_MAX": "MB",
	"RENDER_VIDEO_MEM_USED": "MB", "RENDER_TEXTURE_MEM_USED": "MB",
	"RENDER_VERTEX_MEM_USED": "MB", "RENDER_USAGE_VIDEO_MEM_TOTAL": "MB",
	"gpu": "ms", "frt_frame": "ms", "frt_idle": "ms", "frt_phys": "ms",
	"frt_phys_sum": "ms", "frt_render": "ms", "frt_sync": "ms", "frt_other": "ms",
}


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_update_hz(20.0)
	set_input_hz(20.0)
	connect("imgui_frame", self, "_on_imgui_frame")
	request_redraw()


func _on_imgui_frame() -> void:
	if hud == null or hud.metrics == null:
		return
	has_implot = has_method("implot_begin_plot")
	if is_key_pressed(KEY_F1):
		hud.visible = not hud.visible
	var m = hud.metrics
	_draw_mini(m)
	if hud.visible:
		_draw_full(m)


func _unit(name: String) -> String:
	return UNITS.get(name, "")


func _color(fps: float) -> Color:
	if fps >= 55.0:
		return Color(0.35, 1.0, 0.45)
	if fps >= 30.0:
		return Color(1.0, 0.85, 0.3)
	return Color(1.0, 0.35, 0.35)


# --- Widget mini -------------------------------------------------------------------

func _draw_mini(m) -> void:
	var s: float = mini_scale
	var w: float = 220.0 * s
	var h: float = 76.0 * s
	var vp: Vector2 = get_viewport_rect().size
	var pos := Vector2(8.0, 8.0)
	if mini_corner == 1 or mini_corner == 3:
		pos.x = vp.x - w - 8.0
	if mini_corner == 2 or mini_corner == 3:
		pos.y = vp.y - h - 8.0

	set_next_window_pos(pos, true)
	set_next_window_size(Vector2(w, h), true)
	set_next_window_bg_alpha(0.55)
	var flags := WINDOW_NO_DECORATION | WINDOW_NO_MOVE | WINDOW_NO_RESIZE | WINDOW_NO_SAVED_SETTINGS | WINDOW_NO_SCROLLBAR | WINDOW_NO_TITLE_BAR | WINDOW_NO_BRING_TO_FRONT_ON_FOCUS
	if begin("##debug_mini", flags):
		var fps: float = m.latest.get("TIME_FPS", Performance.get_monitor(Performance.TIME_FPS))
		var mem: float = m.latest.get("MEMORY_STATIC", Performance.get_monitor(Performance.MEMORY_STATIC) * m.MB)
		var draws: float = m.latest.get("RENDER_DRAW_CALLS_IN_FRAME", 0.0)
		var verts: float = m.latest.get("RENDER_VERTICES_IN_FRAME", 0.0)
		text_colored(_color(fps), "FPS %.0f" % fps)
		same_line()
		text("mem %.0f MB" % mem)
		text("draws %.0f  verts %.0f" % [draws, verts])
		# FPS: TIME_PROCESS casi siempre vale 0 en este motor (se actualiza bajo una guarda
		# interna) y la linea quedaba plana en el borde, invisible.
		var spark = m.series.get("TIME_FPS")
		if spark != null and spark.size() > 1:
			if has_implot:
				var plot_flags := IMPLOT_FLAGS_CANVAS_ONLY | IMPLOT_FLAGS_NO_INPUTS
				if implot_begin_plot("##spark", Vector2(w - 14.0, h - 50.0), plot_flags):
					implot_setup_axes("", "", IMPLOT_AXIS_NO_DECORATIONS | IMPLOT_AXIS_AUTOFIT, IMPLOT_AXIS_NO_DECORATIONS | IMPLOT_AXIS_AUTOFIT)
					implot_plot_line("##ft", _index_pool(spark.size()), _pool(spark))
					implot_end_plot()
			else:
				# Sin min/max: los defaults son autoescala (0.0, 0.0 fijaba un rango vacio).
				plot_lines("##spark", _pool(spark), "")
		if is_item_hovered() and is_mouse_clicked(0):
			hud.visible = true
	end()


# --- HUD completo --------------------------------------------------------------

func _draw_full(m) -> void:
	var vp: Vector2 = get_viewport_rect().size
	set_next_window_pos(Vector2(vp.x * 0.08, vp.y * 0.08), true)
	set_next_window_size(Vector2(vp.x * 0.84, vp.y * 0.84), true)
	set_next_window_bg_alpha(0.88)
	var flags := WINDOW_NO_SAVED_SETTINGS
	if begin("Debug HUD (motor)##debug_hud", flags, true):
		if not is_window_open():
			hud.visible = false
		if begin_tab_bar("##hud_tabs"):
			if begin_tab_item("Graficas"):
				_tab_graphs(m)
				end_tab_item()
			if begin_tab_item("Monitores"):
				_tab_monitors(m)
				end_tab_item()
			end_tab_bar()
	end()


func _available(name: String, m) -> bool:
	var arr = m.series.get(name)
	return arr != null and arr.size() > 1


# Con FRT_PERF el grupo GPU va primero para que se vea sin scroll.
func _ordered_groups(m) -> Array:
	var out := []
	var frt: bool = m.profile.get("frt_perf", false)
	if frt:
		for group in GROUPS:
			if group[0] == "GPU":
				out.append(group)
	for group in GROUPS:
		if group[0] == "GPU" and frt:
			continue
		out.append(group)
	return out


func _tab_graphs(m) -> void:
	if m.frame < 2:
		text("Sin datos todavia")
		return
	var avail: Vector2 = get_content_region_avail()
	var plot_h: float = max((avail.y - 30.0) / 3.0, 90.0)
	for group in _ordered_groups(m):
		var names := []
		for name in group[1]:
			if _available(name, m):
				names.append(name)
		if names.size() == 0:
			continue
		if tree_node(group[0], TREE_NODE_DEFAULT_OPEN):
			if has_implot:
				if implot_begin_plot(group[0], Vector2(-1, plot_h)):
					implot_setup_axes("", "", IMPLOT_AXIS_AUTOFIT, IMPLOT_AXIS_AUTOFIT)
					for name in names:
						var arr = m.series[name]
						implot_plot_line(name, _index_pool(arr.size()), _pool(arr))
					implot_end_plot()
			else:
				for name in names:
					plot_lines(name, _pool(m.series[name]), "", 0.0, 0.0, Vector2(-1, plot_h * 0.5))
			tree_pop()


func _tab_monitors(m) -> void:
	var avail: Vector2 = get_content_region_avail()
	var rows := []
	for entry in m.MONITORS:
		rows.append(entry[0])
	if m.profile.get("frt_perf", false):
		for name in m.FRT_SERIES:
			if m.series.has(name):
				rows.append(name)
	if m.series.has("collector_us"):
		rows.append("collector_us")
	if begin_child("##hud_mon", Vector2(-1, max(avail.y - 8.0, 80.0))):
		if begin_table("##hud_mon_table", 5, TABLE_BORDERS | TABLE_ROW_BG | TABLE_RESIZABLE):
			table_setup_column("Monitor")
			table_setup_column("Actual")
			table_setup_column("Min")
			table_setup_column("Max")
			table_setup_column("Media")
			table_headers_row()
			for name in rows:
				var st: Dictionary = m.stats(name)
				var unit: String = _unit(name)
				table_next_row()
				table_next_column()
				text(name)
				table_next_column()
				text("%.2f %s" % [st["latest"], unit])
				table_next_column()
				text("%.2f" % st["min"])
				table_next_column()
				text("%.2f" % st["max"])
				table_next_column()
				text("%.2f" % st["avg"])
			end_table()
	end_child()


# --- Helpers de plots ----------------------------------------------------------

func _index_pool(n: int) -> PoolRealArray:
	var out := PoolRealArray()
	out.resize(n)
	for i in range(n):
		out[i] = i
	return out


func _pool(values: Array) -> PoolRealArray:
	var out := PoolRealArray()
	out.resize(values.size())
	for i in range(values.size()):
		out[i] = values[i]
	return out
