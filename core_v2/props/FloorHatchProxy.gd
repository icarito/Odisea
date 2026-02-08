extends Spatial

func interact():
	if has_node("ValveWheel"):
		$ValveWheel.interact()
