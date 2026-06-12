# app_registry.gd
# Static registry for OdiseaOS apps

class_name AppRegistry

const APPS = {
	"CALC": {
		"name": "Calculator",
		"window_title": "OYS-CALC",
		"script": "res://core_v2/ui/retro/OysCalc.gd",
		"icon": null
	},
	"CAMERAS": {
		"name": "Surveillance",
		"window_title": "SURVEILLANCE",
		"script": "res://core_v2/ui/retro/OysCameras.gd",
		"tscn": "res://core_v2/ui/retro/OysCameras.tscn",
		"icon": null
	},
	"STATUS": {
		"name": "System Status",
		"window_title": "STATUS",
		"script": "res://core_v2/ui/retro/OysStatus.gd",
		"tscn": "res://core_v2/ui/retro/OysStatus.tscn",
		"icon": null
	},
	"NODESCAN": {
		"name": "Node Scanner",
		"window_title": "NODE-SCAN",
		"script": "res://core_v2/ui/retro/NodeScan.gd",
		"icon": null
	}
}
