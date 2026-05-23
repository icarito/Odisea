extends Reference
class_name GravityModes

# FD-040 gravity regimes. Keep these integer values stable: controller
# snapshots and OYS/debug tooling may serialize them directly.

enum Mode {
	STANDARD_1G,
	SPIN_WALKABLE,
	ZERO_G,
	SPIN_DYNAMIC
}

const GRAVITY_MODE_STANDARD_1G := Mode.STANDARD_1G
const GRAVITY_MODE_SPIN_WALKABLE := Mode.SPIN_WALKABLE
const GRAVITY_MODE_ZERO_G := Mode.ZERO_G
const GRAVITY_MODE_SPIN_DYNAMIC := Mode.SPIN_DYNAMIC

static func is_valid_mode(mode: int) -> bool:
	return mode >= Mode.STANDARD_1G and mode <= Mode.SPIN_DYNAMIC

static func mode_name(mode: int) -> String:
	match mode:
		Mode.STANDARD_1G:
			return "STANDARD_1G"
		Mode.SPIN_WALKABLE:
			return "SPIN_WALKABLE"
		Mode.ZERO_G:
			return "ZERO_G"
		Mode.SPIN_DYNAMIC:
			return "SPIN_DYNAMIC"
		_:
			return "UNKNOWN"

static func is_walkable(mode: int) -> bool:
	return mode == Mode.STANDARD_1G or mode == Mode.SPIN_WALKABLE

static func is_spin(mode: int) -> bool:
	return mode == Mode.SPIN_WALKABLE or mode == Mode.SPIN_DYNAMIC

static func is_zero_g(mode: int) -> bool:
	return mode == Mode.ZERO_G
