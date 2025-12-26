extends Node

var provider

func _ready():
    provider = InputProviderV2.new()

func _physics_process(delta):
    var data = provider.get_frame_input()
    print(data.move_vec, " jump=", data.jump)