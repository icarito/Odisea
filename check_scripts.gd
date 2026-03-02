extends SceneTree
func _init():
    load("res://core_v2/ui/retro/OysCalc.gd").new()
    load("res://core_v2/ui/retro/NodeScan.gd").new()
    print("OysCalc and NodeScan syntax OK")
    quit()
