extends Reference
# Sin class_name: se consume con preload().
#
# Episodios de prueba que el menu principal ofrece en "Experimentos". Agregar uno = una linea.
# Toda escena de esta lista debe estar tambien como raiz en export_presets.cfg (export_files):
# los globs del export no caminan dependencias (scripts/check_export_presets.py).

const LIST := [
	{"id": "scaffold_flat", "title": "Andamio", "scene": "res://core_v2/levels/scaffold_run/ScaffoldRunLab.tscn"},
	{"id": "scaffold_orbit", "title": "Andamio orbital", "scene": "res://core_v2/levels/scaffold_run/ScaffoldRunOrbit.tscn"},
	{"id": "hull_underdeck", "title": "Entrecasco", "scene": "res://core_v2/levels/hull_underdeck/HullUnderdeck.tscn"},
	{"id": "hull_sections", "title": "Secciones", "scene": "res://core_v2/levels/hull_underdeck/HullSections.tscn"},
	{"id": "bay_vertical", "title": "Pozo radial", "scene": "res://core_v2/levels/bay_vertical/BayVertical.tscn"},
	{"id": "ark_run", "title": "Del hub al motor", "scene": "res://core_v2/levels/ark_run/ArkRunSlice.tscn"},
	{"id": "spin_lab", "title": "SpinLab", "scene": "res://core_v2/levels/spin_lab/SpinLab.tscn"},
	{"id": "machine_bay", "title": "Maquinaria", "scene": "res://core_v2/levels/machines/MachineBay.tscn"},
]
