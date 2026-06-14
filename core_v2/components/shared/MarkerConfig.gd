extends Resource
class_name MarkerConfig

# MarkerConfig.gd - Resource for Interaction Marker configuration

export(String) var label := ""
export(Texture) var icon: Texture = null
export(String) var hint := ""
export(String) var locked_text := "LOCKED"
export(float) var interaction_range := 5.0
export(bool) var off_screen := true
export(int) var priority := 1 # 0 = critical
export(float) var screen_margin := 24.0
export(Color) var accent_color := Color(0.0, 1.0, 1.0) # Default accent

# Callable equivalent in Godot 3.x
var is_locked: FuncRef = null
