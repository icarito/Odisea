extends Spatial
# Prueba de factibilidad del modulo slug del fork (SlugLabel3D) en el Anbernic.
#
# Arma un panel tipo terminal de criocapsula (titulo grande + 7 lineas de
# cuerpo + una linea de numeros que cambia cada frame) en tres modos, elegidos
# por la env SLUG_PROBE_MODE:
#   slug     -> SlugLabel3D (texto 3D vectorial GLES3)
#   label3d  -> Label3D con DynamicFont (rasterizado)
#   viewport -> Control con Labels dentro de un Viewport 960x600, en un quad
#               (asi dibuja el terminal actual del juego)
#
# Mide frame time tras 5 s de warm-up y 20 s de muestreo (mediana y p95), deja
# una captura del viewport y escribe user://slug_probe.json; despues sale.
#
# Todo se arma en codigo: la escena es solo un Spatial con este script.

const HEADING_FONT_PATH := "res://fonts/Heading_Sixtyfour.ttf"
const BODY_FONT_PATH := "res://fonts/Body_Silkscreen.ttf"
const NOTO_FONT_PATH := "res://fonts/NotoSans-Regular.ttf"

const WARMUP_S := 5.0
const SAMPLE_S := 20.0
const HARD_TIMEOUT_S := WARMUP_S + SAMPLE_S + 15.0

const VIEWPORT_W := 960
const VIEWPORT_H := 600

# Panel en unidades de mundo, centrado a PANEL_Z por delante de la camara.
const PANEL_W := 5.0
const PANEL_H := 3.125
const PANEL_Z := -4.0

# Tamanos en em (unidades de mundo por em). Con el viewport de 960 px sobre
# PANEL_W, el factor es 192 px/unidad: estos em equivalen a 36 / 20 / 28 px.
const TITLE_EM := 0.1875
const BODY_EM := 0.104
const NUM_EM := 0.146
const LABEL3D_PIXEL_SIZE := TITLE_EM / 36.0

const TITLE_TEXT := "ODISEA // NUCLEO"
const BODY_LINES := [
	"> estado: CRITICO",
	"> criocapsula: C-07",
	"> presion: 101.3 kPa",
	"> temperatura: 21.5 C",
	"> integridad: 98.2 %",
	"> enlace: SINCRONIZADO",
	"> operador: ELIAS V.",
]
const TITLE_COLOR := Color(0.75, 0.92, 1.0)
const BODY_COLOR := Color(0.55, 0.95, 0.65)
const NUM_COLOR := Color(1.0, 0.78, 0.35)

var _mode := "slug"
var _warmup_s := WARMUP_S
var _sample_s := SAMPLE_S
var _hard_timeout_s := HARD_TIMEOUT_S
var _elapsed := 0.0
var _done := false
var _frames := 0
var _samples := []
var _screenshot_path := ""
var _shot_taken := false

var _slug_ok := false
var _slug_info := {}
var _numbers_node: Object = null
var _use_fallback := true


func _ready() -> void:
	_mode = OS.get_environment("SLUG_PROBE_MODE")
	if _mode == "":
		_mode = "slug"
	_warmup_s = _env_float("SLUG_PROBE_WARMUP", WARMUP_S)
	_sample_s = _env_float("SLUG_PROBE_SAMPLE", SAMPLE_S)
	_hard_timeout_s = _warmup_s + _sample_s + 15.0
	_use_fallback = OS.get_environment("SLUG_PROBE_FALLBACK") != "0"
	OS.set_window_title("slug_probe_%s" % _mode)

	_setup_world()
	_setup_camera()
	_setup_panel()

	_slug_ok = ClassDB.class_exists("SlugFont") and ClassDB.class_exists("SlugLabel3D")
	if _slug_ok:
		_slug_info = _build_slug_fonts()

	match _mode:
		"label3d":
			_build_label3d()
		"viewport":
			_build_viewport()
		_:
			if _slug_ok:
				_build_slug()
			else:
				var fallback := "no hay modulo slug en este binario; uso label3d"
				push_warning("[slug_probe] %s" % fallback)
				_build_label3d()

	_update_numbers()


# --------------------------------------------------------------------------
# Escena base
# --------------------------------------------------------------------------

func _setup_world() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.035)
	env.ambient_light_color = Color(0.16, 0.17, 0.2)
	env.ambient_light_energy = 1.0
	world_env.environment = env
	add_child(world_env)


func _setup_camera() -> void:
	var camera := Camera.new()
	camera.current = true
	camera.fov = 70.0
	add_child(camera)


func _setup_panel() -> void:
	_add_quad(Vector2(PANEL_W + 0.12, PANEL_H + 0.12), PANEL_Z - 0.02, Color(0.3, 0.5, 0.6))
	_add_quad(Vector2(PANEL_W, PANEL_H), PANEL_Z, Color(0.015, 0.03, 0.04))


func _add_quad(size: Vector2, z: float, color: Color) -> MeshInstance:
	var mesh := QuadMesh.new()
	mesh.size = size
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.albedo_color = color
	mesh.material = mat
	var inst := MeshInstance.new()
	inst.mesh = mesh
	inst.translation = Vector3(0, 0, z)
	add_child(inst)
	return inst


# --------------------------------------------------------------------------
# Fuentes
# --------------------------------------------------------------------------

func _font_data(path: String) -> DynamicFontData:
	var res = load(path)
	if res is DynamicFontData:
		return res as DynamicFontData
	var data := DynamicFontData.new()
	data.font_path = path
	return data


func _dynamic_font(data: DynamicFontData, size: int) -> DynamicFont:
	var font := DynamicFont.new()
	font.font_data = data
	font.size = size
	return font


# --------------------------------------------------------------------------
# Modo slug
# --------------------------------------------------------------------------

func _build_slug_fonts() -> Dictionary:
	# Slug exige contornos cuadraticos (TrueType): prueba las fuentes del juego
	# y cae a NotoSans si alguna no construye.
	var heading := _slug_font_from(HEADING_FONT_PATH)
	var body := _slug_font_from(BODY_FONT_PATH)
	if not heading.is_valid():
		push_warning("[slug_probe] Heading no valida en Slug; uso NotoSans")
		heading = _slug_font_from(NOTO_FONT_PATH)
	if not body.is_valid():
		push_warning("[slug_probe] Body no valida en Slug; uso NotoSans")
		body = _slug_font_from(NOTO_FONT_PATH)
	return {
		"title": heading,
		"body": body,
		"heading_valid": heading.is_valid(),
		"body_valid": body.is_valid(),
		"heading_glyphs": heading.get_glyph_count() if heading.is_valid() else 0,
		"body_glyphs": body.get_glyph_count() if body.is_valid() else 0,
		"heading_build_us": heading.get_build_time_usec() if heading.is_valid() else 0,
		"body_build_us": body.get_build_time_usec() if body.is_valid() else 0,
		"heading_max_curves": heading.get_max_curves_per_band() if heading.is_valid() else 0,
		"body_max_curves": body.get_max_curves_per_band() if body.is_valid() else 0,
	}


func _slug_font_from(path: String) -> SlugFont:
	var font := SlugFont.new()
	font.font_data = _font_data(path)
	return font


func _slug_label(text: String, font: SlugFont, size: float) -> SlugLabel3D:
	var label := SlugLabel3D.new()
	label.text = text
	label.font = font
	label.size = size
	# El modulo solo dibuja bajo GLES3; si no, cae al Label3D interno. Le damos
	# una fuente para que el fallback sea visible (como lo haria el juego).
	if _use_fallback:
		label.fallback_font = _dynamic_font(_fallback_data(font), 64)
	add_child(label)
	return label


func _fallback_data(font: SlugFont) -> DynamicFontData:
	if font == _slug_info.get("title"):
		return _font_data(HEADING_FONT_PATH)
	return _font_data(BODY_FONT_PATH)


func _build_slug() -> void:
	var title := _slug_label(TITLE_TEXT, _slug_info.title, TITLE_EM)
	title.translation = Vector3(0, 1.2, PANEL_Z + 0.05)
	title.modulate = TITLE_COLOR

	var body := _slug_label(PoolStringArray(BODY_LINES).join("\n"), _slug_info.body, BODY_EM)
	body.align = SlugLabel3D.ALIGN_LEFT
	body.line_spacing = 0.4
	body.translation = Vector3(-2.25, 0.1, PANEL_Z + 0.05)
	body.modulate = BODY_COLOR

	_numbers_node = _slug_label("", _slug_info.body, NUM_EM)
	_numbers_node.translation = Vector3(0, -1.05, PANEL_Z + 0.05)
	_numbers_node.modulate = NUM_COLOR


# --------------------------------------------------------------------------
# Modo label3d
# --------------------------------------------------------------------------

func _build_label3d() -> void:
	var heading_data := _font_data(HEADING_FONT_PATH)
	var body_data := _font_data(BODY_FONT_PATH)

	var title := Label3D.new()
	title.text = TITLE_TEXT
	title.font = _dynamic_font(heading_data, 36)
	title.pixel_size = LABEL3D_PIXEL_SIZE
	title.modulate = TITLE_COLOR
	title.translation = Vector3(0, 1.2, PANEL_Z + 0.05)
	add_child(title)

	var body := Label3D.new()
	body.text = PoolStringArray(BODY_LINES).join("\n")
	body.font = _dynamic_font(body_data, 20)
	body.pixel_size = LABEL3D_PIXEL_SIZE
	body.horizontal_alignment = Label3D.ALIGN_LEFT
	body.line_spacing = 0.4 * 20.0
	body.modulate = BODY_COLOR
	body.translation = Vector3(-2.25, 0.1, PANEL_Z + 0.05)
	add_child(body)

	var numbers := Label3D.new()
	numbers.font = _dynamic_font(body_data, 28)
	numbers.pixel_size = LABEL3D_PIXEL_SIZE
	numbers.modulate = NUM_COLOR
	numbers.translation = Vector3(0, -1.05, PANEL_Z + 0.05)
	add_child(numbers)
	_numbers_node = numbers


# --------------------------------------------------------------------------
# Modo viewport
# --------------------------------------------------------------------------

func _build_viewport() -> void:
	var viewport := Viewport.new()
	viewport.size = Vector2(VIEWPORT_W, VIEWPORT_H)
	viewport.usage = Viewport.USAGE_2D
	viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)

	var root := Control.new()
	root.rect_size = Vector2(VIEWPORT_W, VIEWPORT_H)
	viewport.add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.03, 0.04)
	bg.rect_size = Vector2(VIEWPORT_W, VIEWPORT_H)
	root.add_child(bg)

	var heading_data := _font_data(HEADING_FONT_PATH)
	var body_data := _font_data(BODY_FONT_PATH)

	var title := Label.new()
	title.text = TITLE_TEXT
	title.add_font_override("font", _dynamic_font(heading_data, 36))
	title.add_color_override("font_color", TITLE_COLOR)
	title.rect_position = Vector2(48, 44)
	root.add_child(title)

	var body := Label.new()
	body.text = PoolStringArray(BODY_LINES).join("\n")
	body.add_font_override("font", _dynamic_font(body_data, 20))
	body.add_color_override("font_color", BODY_COLOR)
	body.rect_position = Vector2(48, 150)
	root.add_child(body)

	var numbers := Label.new()
	numbers.add_font_override("font", _dynamic_font(body_data, 28))
	numbers.add_color_override("font_color", NUM_COLOR)
	numbers.rect_position = Vector2(48, 520)
	root.add_child(numbers)
	_numbers_node = numbers

	var quad := _add_quad(Vector2(PANEL_W, PANEL_H), PANEL_Z, Color(1, 1, 1))
	var mat := (quad.mesh as QuadMesh).material as SpatialMaterial
	mat.albedo_color = Color(1, 1, 1)
	mat.albedo_texture = viewport.get_texture()
	# Godot 3 entrega la ViewportTexture con la Y invertida sobre el quad.
	mat.uv1_scale = Vector3(1, -1, 1)
	mat.uv1_offset = Vector3(0, 1, 0)


# --------------------------------------------------------------------------
# Medición
# --------------------------------------------------------------------------

func _update_numbers() -> void:
	if _numbers_node == null:
		return
	var text := "T+%07.2f  FPS %03d  FRAME %05d" % [
		_elapsed, Engine.get_frames_per_second(), _frames
	]
	_numbers_node.set("text", text)


func _process(delta: float) -> void:
	_elapsed += delta
	_frames += 1
	_update_numbers()

	if _elapsed >= _warmup_s and _elapsed < _warmup_s + _sample_s:
		_samples.append(delta)

	if not _done and (_elapsed >= _warmup_s + _sample_s or _elapsed >= _hard_timeout_s):
		_done = true
		_finalize()


func _save_screenshot() -> String:
	var img := get_viewport().get_texture().get_data()
	img.flip_y()
	var path := "user://slug_probe_%s.png" % _mode
	if img.save_png(path) != OK:
		return ""
	return ProjectSettings.globalize_path(path)


func _finalize() -> void:
	if not _shot_taken:
		_shot_taken = true
		_screenshot_path = _save_screenshot()
	var payload := {
		"mode": _mode,
		"engine": Engine.get_version_info().string,
		"os": OS.get_name(),
		"video_driver": _video_driver_name(),
		"video_driver_index": OS.get_current_video_driver(),
		"driver_constants": {
			"gles2": OS.VIDEO_DRIVER_GLES2,
			"gles3": OS.VIDEO_DRIVER_GLES3,
		},
		"adapter": VisualServer.get_video_adapter_name(),
		"window_size": [OS.window_size.x, OS.window_size.y],
		"warmup_s": _warmup_s,
		"sample_s": _sample_s,
		"frames": _frames,
		"sample_count": _samples.size(),
		"sampled_total_s": _sum(_samples),
		"screenshot": _screenshot_path,
	}
	if _samples.empty():
		payload["error"] = "sin muestras de frame time"
	else:
		var sorted := _samples.duplicate()
		sorted.sort()
		var total := _sum(sorted)
		payload["avg_fps"] = (sorted.size() / total) if total > 0.0 else 0.0
		payload["median_ms"] = _percentile(sorted, 0.5) * 1000.0
		payload["p95_ms"] = _percentile(sorted, 0.95) * 1000.0
		payload["p99_ms"] = _percentile(sorted, 0.99) * 1000.0
		payload["min_ms"] = sorted[0] * 1000.0
		payload["max_ms"] = sorted[sorted.size() - 1] * 1000.0

	if _mode == "slug":
		var slug_fallback := (not _slug_ok) or (OS.get_current_video_driver() == OS.VIDEO_DRIVER_GLES2)
		if not _slug_info.get("heading_valid", false):
			slug_fallback = true
		if not _slug_info.get("body_valid", false):
			slug_fallback = true
		payload["slug"] = {
			"module_available": _slug_ok,
			"heading_valid": _slug_info.get("heading_valid", false),
			"body_valid": _slug_info.get("body_valid", false),
			"fallback_active": slug_fallback,
			"fallback_font_set": _use_fallback,
			"heading_glyphs": _slug_info.get("heading_glyphs", 0),
			"body_glyphs": _slug_info.get("body_glyphs", 0),
			"heading_build_us": _slug_info.get("heading_build_us", 0),
			"body_build_us": _slug_info.get("body_build_us", 0),
			"heading_max_curves_per_band": _slug_info.get("heading_max_curves", 0),
			"body_max_curves_per_band": _slug_info.get("body_max_curves", 0),
		}

	var path := _write_json(payload)
	print("[slug_probe] mode=%s json=%s screenshot=%s" % [_mode, path, _screenshot_path])
	print("[slug_probe] %s" % JSON.print(payload))
	get_tree().quit(0)


func _write_json(payload: Dictionary) -> String:
	var file := File.new()
	if file.open("user://slug_probe.json", File.WRITE) != OK:
		return ""
	file.store_string(JSON.print(payload, "  "))
	file.close()
	return OS.get_user_data_dir().plus_file("slug_probe.json")


func _env_float(name: String, fallback: float) -> float:
	var raw := OS.get_environment(name)
	if raw == "":
		return fallback
	return float(raw)


func _video_driver_name() -> String:
	var driver := OS.get_current_video_driver()
	if driver == OS.VIDEO_DRIVER_GLES2:
		return "GLES2"
	if driver == OS.VIDEO_DRIVER_GLES3:
		return "GLES3"
	return "desconocido"


func _sum(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total


func _percentile(sorted_values: Array, p: float) -> float:
	if sorted_values.empty():
		return 0.0
	var idx := int(round(p * (sorted_values.size() - 1)))
	idx = int(clamp(idx, 0, sorted_values.size() - 1))
	return sorted_values[idx]
