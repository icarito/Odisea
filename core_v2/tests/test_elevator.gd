extends Spatial

func _ready():
    # Force test camera to be current, overriding PropStage or Player
    if has_node("Camera"):
        $Camera.make_current()

    # Manual Trigger Fail-safe for Headless Environment
    # In case OLCS auto-build takes too long or fails in this stripped env
    if not Engine.editor_hint:
        yield(get_tree().create_timer(3.0), "timeout")
        var input_node = get_node_or_null("ElevatorProp/Input_Floor1")
        if input_node:
            print("[ElevatorTestScene] Manually triggering Floor 1 Input...")
            input_node.set_active(true)
