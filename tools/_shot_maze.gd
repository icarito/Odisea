extends SceneTree
func _init():
    call_deferred("_run")
func _run():
    var maze = load("res://scenes/levels/act0_duct_maze.tscn").instance()
    get_root().add_child(maze)
    # red reference ring at the cylinder wall (r=30)
    var imm = ImmediateGeometry.new()
    var m = SpatialMaterial.new(); m.flags_unshaded = true; m.albedo_color = Color(1,0,0)
    imm.material_override = m
    get_root().add_child(imm)
    imm.begin(Mesh.PRIMITIVE_LINE_STRIP)
    for i in range(65):
        var a = TAU*i/64.0
        imm.add_vertex(Vector3(30*cos(a),0,30*sin(a)))
    imm.end()
    var light = DirectionalLight.new(); get_root().add_child(light)
    light.rotation_degrees = Vector3(-45,-35,0)
    var cam = Camera.new(); get_root().add_child(cam)
    cam.translation = Vector3(55, 60, 55)
    cam.look_at(Vector3(0,15,0), Vector3.UP)
    cam.far = 600; cam.make_current()
    VisualServer.set_default_clear_color(Color(0.06,0.06,0.09))
    for _i in range(10): yield(self,"idle_frame")
    yield(VisualServer,"frame_post_draw")
    var img = get_root().get_viewport().get_texture().get_data()
    img.flip_y()
    img.save_png("user://maze_shot.png")
    print("SHOT_DONE")
    quit()
