tool
extends EditorPlugin

func _enter_tree():
	# This plugin doesn't need to add UI elements or custom types for now.
	# The real work is done by HunyuanRetargeter.gd as an import script.
	print("Hunyuan Retargeter plugin enabled.")

func _exit_tree():
	print("Hunyuan Retargeter plugin disabled.")
