extends CanvasLayer

# CaptureOverlay.gd
# Manages visual screen transitions (blue stasis tint and black screen fade) during captures.

onready var stasis_tint := $StasisTint
onready var black_fade := $BlackFade
onready var tween := $Tween

func _ready() -> void:
	stasis_tint.color = Color(0.0, 0.4, 0.8, 0.0)
	black_fade.color = Color(0.0, 0.0, 0.0, 0.0)

func fade_stasis_in(duration: float = 0.5) -> void:
	tween.interpolate_property(
		stasis_tint,
		"color",
		Color(0.0, 0.4, 0.8, 0.0),
		Color(0.0, 0.4, 0.8, 0.45),
		duration,
		Tween.TRANS_SINE,
		Tween.EASE_OUT
	)
	tween.start()
	yield(tween, "tween_all_completed")

func fade_black_out(duration: float = 0.5) -> void:
	# Fades the black_fade node to black (cover screen)
	tween.interpolate_property(
		black_fade,
		"color",
		Color(0.0, 0.0, 0.0, 0.0),
		Color(0.0, 0.0, 0.0, 1.0),
		duration,
		Tween.TRANS_SINE,
		Tween.EASE_IN_OUT
	)
	tween.start()
	yield(tween, "tween_all_completed")

func fade_stasis_out(duration: float = 0.3) -> void:
	tween.interpolate_property(
		stasis_tint,
		"color",
		stasis_tint.color,
		Color(0.0, 0.4, 0.8, 0.0),
		duration,
		Tween.TRANS_SINE,
		Tween.EASE_IN_OUT
	)
	tween.start()
	yield(tween, "tween_all_completed")

func fade_black_in(duration: float = 0.5) -> void:
	# Fades the black cover away (reveal screen)
	tween.interpolate_property(
		black_fade,
		"color",
		black_fade.color,
		Color(0.0, 0.0, 0.0, 0.0),
		duration,
		Tween.TRANS_SINE,
		Tween.EASE_IN_OUT
	)
	tween.start()
	yield(tween, "tween_all_completed")

func reset_overlay() -> void:
	tween.stop_all()
	stasis_tint.color = Color(0.0, 0.4, 0.8, 0.0)
	black_fade.color = Color(0.0, 0.0, 0.0, 0.0)
