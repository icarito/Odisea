extends CanvasLayer

# UIManager (autoload: "UIManager")
# Responsibility: A single point of communication for displaying UI elements
# like menus, HUDs, and modal messages.

# --- Properties ---
var main_menu_scene: PackedScene = preload("res://scenes/Menu.tscn") # Adjust path if needed
var hud_instance: Node = null
var modal_instance: AcceptDialog = null

# --- Public API ---

func show_main_menu() -> void:
	# Ensure HUD is hidden
	toggle_hud(false)
	
	# Instance and show the main menu
	var menu = main_menu_scene.instance()
	get_tree().get_root().add_child(menu)
	# The menu should handle its own lifecycle, including `queue_free()` on exit.

func show_alert_modal(message: String, title: String = "Alert") -> void:
	if not is_instance_valid(modal_instance):
		modal_instance = AcceptDialog.new()
		modal_instance.name = "AlertDialog"
		get_tree().get_root().add_child(modal_instance)
		
	modal_instance.dialog_text = message
	modal_instance.window_title = title
	modal_instance.popup_centered()

func toggle_hud(visible: bool) -> void:
	if not is_instance_valid(hud_instance):
		# This assumes you have a HUD scene that should be instanced.
		# Replace "res://scenes/ui/HUD.tscn" with the actual path.
		var hud_scene = load("res://scenes/ui/HUD.tscn") 
		if hud_scene:
			hud_instance = hud_scene.instance()
			add_child(hud_instance) # Add as a child of the UIManager CanvasLayer
		else:
			push_error("UIManager: HUD scene not found. Cannot toggle visibility.")
			return
			
	hud_instance.visible = visible

# --- Scene-specific UI Management ---

# Call this from your level/game scene's _ready function
func set_hud(hud_node: Node) -> void:
	if is_instance_valid(hud_instance) and hud_instance != hud_node:
		hud_instance.queue_free()
	hud_instance = hud_node
	# Ensure the HUD is parented to the UIManager to persist across scene changes if needed
	if hud_instance.get_parent() != self:
		hud_instance.get_parent().remove_child(hud_instance)
		self.add_child(hud_instance)

func _ready() -> void:
	# Making sure the UIManager is always on top of other 2D rendering.
	layer = 128
