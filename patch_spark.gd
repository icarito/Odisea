extends SceneTree

func _init():
    var packed = load("res://core_v2/props/SparkEmitterV2.tscn")
    var emitter = packed.instance()
    
    if not emitter.has_node("SparkSound"):
        var sound = AudioStreamPlayer3D.new()
        sound.name = "SparkSound"
        sound.unit_db = -5.0
        sound.max_distance = 20.0
        emitter.add_child(sound)
        sound.owner = emitter
    
    var new_packed = PackedScene.new()
    new_packed.pack(emitter)
    ResourceSaver.save("res://core_v2/props/SparkEmitterV2.tscn", new_packed)
    print("SparkSound added to SparkEmitterV2.tscn")
    quit()
