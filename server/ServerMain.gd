extends Node
## Headless dedicated server entry point.
##
## Run with:
##   godot --headless --path monopolia server/ServerMain.tscn -- --port 27015 --ruleset core:classic
##
## Loads the same packs a client would, then opens an authoritative server. It
## keeps no local player; connected clients drive the game (start, rolls, ...).

func _ready() -> void:
	print("========================================")
	print(" Monopolis dedicated server")
	print("========================================")

	if not ModLoader.loaded:
		ModLoader.load_all()

	var args := _parse_args()
	var port := int(args.get("port", NetworkManager.DEFAULT_PORT))
	var ruleset := str(args.get("ruleset", GameConfig.selected_ruleset))

	if not NetworkManager.start_dedicated(port, ruleset):
		push_error("[Server] Failed to bind port %d" % port)
		get_tree().quit(1)
		return

	print("[Server] Ruleset: %s" % ruleset)
	print("[Server] Signature: %s" % PackRegistry.signature)
	print("[Server] Packs: %s" % str(ModLoader.get_pack_summaries()))
	print("[Server] Waiting for players...")

	NetworkManager.multiplayer.peer_connected.connect(_on_peer_connected)
	NetworkManager.multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_connected(id: int) -> void:
	print("[Server] Peer connected: %d" % id)

func _on_peer_disconnected(id: int) -> void:
	print("[Server] Peer disconnected: %d" % id)

## Parses "--key value" pairs from the user args after the "--" separator.
func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	var argv := OS.get_cmdline_user_args()
	var i := 0
	while i < argv.size():
		var token: String = argv[i]
		if token.begins_with("--"):
			var key := token.substr(2)
			if i + 1 < argv.size() and not argv[i + 1].begins_with("--"):
				out[key] = argv[i + 1]
				i += 2
				continue
			out[key] = true
		i += 1
	return out
