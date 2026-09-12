extends Reference

# HudTabGesture.gd - Tap vs hold de TAB (accion hud_mode) del modo HUD (FD-296 F3, spec 4.1).
# Se alimenta con UNA muestra del stream grabado por tick de fisica (InputDataV2.hud_mode),
# nunca con Input en vivo: el mismo stream en replay da el mismo tap o el mismo hold.

# HOLD_RELEASE: se solto TAB despues de que esa misma pulsacion ya dio HOLD. El dial del hold
# es un cuasimodo: soltar elige lo marcado, o sale si ya se eligio con TAB apretado.
enum { NONE, TAP, HOLD, HOLD_RELEASE }

# 0.4 s a 60 muestras/s (FIXED_DT del replay). Con el mundo pausado, mas espera se siente rota.
const HOLD_TICKS := 24
# El hold es invisible: el overlay avisa ("Mantén TAB...") hasta que se usa una vez. Preferencia
# del jugador, no estado de juego: vive en user://, fuera del snapshot de replay.
const HINT_CFG := "user://suitos_hints.cfg"

var _ticks: int = -1 # -1 = no hay pulsacion pendiente de decidir
var _was_down: bool = false
var _held: bool = false # esta pulsacion ya dio HOLD: su release es HOLD_RELEASE

# La pulsacion ya empezo antes de la primera muestra (el TAB que abrio el modo HUD).
func begin_held() -> void:
	_ticks = 0
	_was_down = true
	_held = false

# Olvida la pulsacion en curso: su release ya no cuenta como tap ni como fin de hold.
func consume() -> void:
	_ticks = -1
	_held = false

# La pulsacion en curso pasa a ser un hold ya, sin esperar el umbral: el dedo del boton del HUD
# empezo a arrastrar, y un arrastre nunca es un tap. Su release sera HOLD_RELEASE.
func promote_to_hold() -> void:
	if not _was_down:
		return
	_ticks = -1
	_held = true

func feed(down: bool) -> int:
	var result: int = NONE
	if down and not _was_down:
		_ticks = 0
		_held = false
	if down and _ticks >= 0:
		_ticks += 1
		if _ticks >= HOLD_TICKS:
			_ticks = -1
			_held = true
			result = HOLD
	elif not down and _was_down:
		if _ticks >= 0:
			_ticks = -1
			result = TAP
		elif _held:
			result = HOLD_RELEASE
		_held = false
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
