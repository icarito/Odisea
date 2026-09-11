extends Reference

# Los botones de AcceptDialog/ConfirmationDialog los crea Godot por codigo y el tema no
# tiene como fijarles un tamaño: con solo el relleno del tema, OK queda chico para un
# dedo. Mismo alto que los botones de FirstRunConsent.
const TOUCH_MIN_SIZE := Vector2(120, 44)

static func fit_for_touch(dialog: AcceptDialog) -> void:
	dialog.get_ok().rect_min_size = TOUCH_MIN_SIZE
	if dialog is ConfirmationDialog:
		(dialog as ConfirmationDialog).get_cancel().rect_min_size = TOUCH_MIN_SIZE
