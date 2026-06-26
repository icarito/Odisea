extends Spatial

onready var spawner = $DuctMazeSpawner

func _ready():
	# The spawner already calls generate() in _ready if not Engine.editor_hint
	# but we can call it explicitly here if needed or to pass custom seed.
	# spawner.generate()
	pass
