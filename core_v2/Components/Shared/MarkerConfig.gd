extends Resource
class_name MarkerConfig

# MarkerConfig.gd - Resource defining interaction marker behavior

export(String) var label := ""
export(Texture) var icon: Texture = null
export(String) var hint := ""
export(String) var locked_text := ""

# is_locked: A FuncRef that returns true if the interaction is locked
var is_locked: FuncRef = null

export(float) var interaction_range := 5.0
export(bool) var off_screen := true
export(int) var priority := 10 # 0 is highest priority
export(float) var screen_margin := 32.0
