extends Node
## Global signal bus and moddable hook system.
##
## Two mechanisms live here:
##  - Godot signals for loosely coupled UI/gameplay events.
##  - A named "hook" registry that packs/DLC use to inject behaviour into the
##    game loop without the core knowing about them ahead of time.

# --- Lifecycle / flow signals -------------------------------------------------
signal packs_loaded(signature: String)
signal game_state_changed(snapshot: Dictionary)
signal local_balance_changed(amount: int)
signal turn_changed(peer_id: int)
signal dice_rolled(peer_id: int, values: Array)
signal player_moved(peer_id: int, from_index: int, to_index: int)
signal chat_message(peer_id: int, text: String)
signal private_state_changed(state: Dictionary)
signal game_action(event_name: String, data: Dictionary)

# --- Networking signals -------------------------------------------------------
signal connection_succeeded()
signal connection_failed(reason: String)
signal server_created()
signal desync_detected(diff: Dictionary)

## hook_name -> Array[Callable]
var _hooks: Dictionary = {}

func add_hook(hook_name: String, callback: Callable, priority: int = 0) -> void:
	if not _hooks.has(hook_name):
		_hooks[hook_name] = []
	_hooks[hook_name].append({"cb": callback, "priority": priority})
	_hooks[hook_name].sort_custom(func(a, b): return a["priority"] > b["priority"])

func remove_hooks_for_object(obj: Object) -> void:
	for hook_name in _hooks.keys():
		_hooks[hook_name] = _hooks[hook_name].filter(
			func(entry): return entry["cb"].get_object() != obj
		)

## Runs every callback registered under `hook_name`, threading `payload`
## through each one. A hook may return a modified Dictionary to replace the
## payload for subsequent hooks; returning null keeps the current payload.
func run_hook(hook_name: String, payload: Dictionary = {}) -> Dictionary:
	if not _hooks.has(hook_name):
		return payload
	var current: Dictionary = payload
	for entry in _hooks[hook_name]:
		var cb: Callable = entry["cb"]
		if not cb.is_valid():
			continue
		var result = cb.call(current)
		if result is Dictionary:
			current = result
	return current

func clear_hooks() -> void:
	_hooks.clear()
