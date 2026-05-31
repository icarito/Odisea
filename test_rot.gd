extends SceneTree
func _init():
    var s = Spatial.new()
    s.rotation_degrees.x = 10
    print("X is ", s.rotation_degrees.x)
    s.rotation_degrees = Vector3(10, 0, 0)
    print("X is now ", s.rotation_degrees.x)
    quit()
