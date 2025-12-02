extends Node

func _ready():
	var anim_player = get_parent().get_node("Pilot/AnimationPlayer")
	if anim_player:
		var walk_anim = anim_player.get_animation("Walk_Loop")
		if walk_anim:
			walk_anim.loop = true
		var run_anim = anim_player.get_animation("Run")
		if run_anim:
			run_anim.loop = true
		var idle_anim = anim_player.get_animation("Idle")
		if idle_anim:
			idle_anim.loop = true			
