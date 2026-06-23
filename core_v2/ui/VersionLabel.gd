# core_v2/ui/VersionLabel.gd
# FD-234: Helper for reading and formatting the application version.
extends Reference

# Lee la versión REAL en ejecución. Tras un update con hot-swap del .pck, el
# project.binary nuevo se monta pero ProjectSettings ya quedó inicializado con la
# versión vieja del boot -> el menú mostraría la versión pre-update. Por eso la
# fuente de verdad es build_meta.json (empaquetado en el .pck activo, que SÍ refleja
# el pck nuevo), con ProjectSettings solo como fallback (editor/dev sin build_meta).
static func get_version_string() -> String:
	var um = Engine.get_main_loop().root.get_node_or_null("/root/UpdateManager") if Engine.get_main_loop() else null
	if um and um.has_method("get_local_build_info"):
		var info = um.get_local_build_info()
		var v = str(info.get("version", ""))
		if v != "" and v != "null":
			return v
	return String(ProjectSettings.get_setting("application/config/version"))

static func get_formatted_version() -> String:
	var v = get_version_string()
	if v == "" or v == "null":
		return "v0.0.0-dev"
	return v
