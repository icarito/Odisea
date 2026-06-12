# app_registry.gd
# Static registry for OdiseaOS apps

class_name AppRegistry

const APPS = {
	"CALC": {
		"name": "Calculator",
		"script": "res://core_v2/ui/retro/OysCalc.gd",
		"icon": null
	},
	"CAMERAS": {
		"name": "Surveillance",
		"script": "res://core_v2/ui/retro/OysCameras.gd",
		"tscn": "res://core_v2/ui/retro/OysCameras.tscn",
		"icon": null
	},
	"STATUS": {
		"name": "System Status",
		"script": "res://core_v2/ui/retro/OysStatus.gd",
		"tscn": "res://core_v2/ui/retro/OysStatus.tscn",
		"icon": null
	},
	"NODESCAN": {
		"name": "Node Scanner",
		"script": "res://core_v2/ui/retro/NodeScan.gd",
		"icon": null
	}
}
