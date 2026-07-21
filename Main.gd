extends Node
## Application entry point. Loads all packs/DLC, then either boots the dedicated
## server (headless / --server) or shows the main menu.

func _ready() -> void:
	if not ModLoader.loaded:
		ModLoader.load_all()
	call_deferred("_route")

func _route() -> void:
	if _is_server_mode():
		get_tree().change_scene_to_file(PackRegistry.resolve_scene(
			"server", "res://server/ServerMain.tscn"))
	else:
		get_tree().change_scene_to_file(PackRegistry.resolve_scene(
			"main_menu", "res://ui/MainMenu.tscn"))

func _is_server_mode() -> bool:
	if "--server" in OS.get_cmdline_user_args():
		return true
	return DisplayServer.get_name() == "headless"
