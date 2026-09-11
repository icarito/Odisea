extends Reference

# HudTabGesture.gd - Tap vs hold de TAB (accion hud_mode) del modo HUD (FD-296 F3, spec 4.1).
# Se alimenta con UNA muestra del stream grabado por tick de fisica (InputDataV2.hud_mode),
# nunca con Input en vivo: el mismo stream en replay da el mismo tap o el mismo hold.

enum { NONE, TAP, HOLD }

# 0.4 s a 60 muestras/s (FIXED_DT del replay). Con el mundo pausado, mas espera se siente rota.
const HOLD_TICKS := 24
# El hold es invisible: el overlay avisa ("Mantén TAB...") hasta que se usa una vez. Preferencia
# del jugador, no estado de juego: vive en user://, fuera del snapshot de replay.
const HINT_CFG := "user://suitos_hints.cfg"

var _ticks: int = -1 # -1 = no hay pulsacion pendiente de decidir
var _was_down: bool = false

# La pulsacion ya empezo antes de la primera muestra (el TAB que abrio el modo HUD).
func begin_held() -> void:
	_ticks = 0
	_was_down = true

# Olvida la pulsacion en curso: su release ya no cuenta como tap.
func consume() -> void:
	_ticks = -1

func feed(down: bool) -> int:
	var result: int = NONE
	if down and not _was_down:
		_ticks = 0
	if down and _ticks >= 0:
		_ticks += 1
		if _ticks >= HOLD_TICKS:
			_ticks = -1
			result = HOLD
	elif not down and _was_down and _ticks >= 0:
		_ticks = -1
		result = TAP
	_was_down = down
	return result

static func hold_discovered() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(HINT_CFG) == OK and bool(cfg.get_value("hints", "hud_hold", false))

static func mark_hold_discovered() -> void:
	var cfg := ConfigFile.new()
	cfg.load(HINT_CFG)
	cfg.set_value("hints", "hud_hold", true)
	cfg.save(HINT_CFG)
