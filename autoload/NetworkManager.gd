extends Node
## Networking layer over Godot's high-level MultiplayerAPI (ENet).
##
## Roles:
##   - server / dedicated: authoritative, owns the GameController.
##   - host: server + a local player (peer 1).
##   - client: keeps only a public mirror of state + its own private balance.
##
## Anti-desync: on connect the server sends its pack signature; the client
## refuses to join (and reports a diff) unless it matches exactly.

const DEFAULT_PORT: int = 27015
const MAX_CLIENTS: int = 8

enum Mode { NONE, HOST, DEDICATED, CLIENT }

var mode: int = Mode.NONE
var game: GameController = null           # server-side only
var _local_peer_id: int = 0
var _event_sequence: int = 0
var _last_received_event: int = 0

# --- Client-side mirror (also used by the host for its own player) ------------
var local_snapshot: Dictionary = {}
var local_board: BoardModel = null
var _local_board_ruleset: String = ""
var local_players: Array = []             # Array[PlayerState]
var local_balance: int = 0
var local_private_state: Dictionary = {}
var last_disconnect_reason: String = ""

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func is_server() -> bool:
	return mode == Mode.HOST or mode == Mode.DEDICATED

func is_host() -> bool:
	return mode == Mode.HOST

func _is_local_player(peer_id: int) -> bool:
	return mode == Mode.HOST and peer_id == 1

# --- Session setup ------------------------------------------------------------

func host_game(port: int = DEFAULT_PORT, ruleset_id: String = "") -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_CLIENTS) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	_local_peer_id = 1
	_init_server_game(ruleset_id)
	# The host is also a player (peer 1); add it directly, no handshake needed.
	game.add_player(1, GameConfig.to_join_payload())
	_broadcast_snapshot()
	_push_balance(1)
	EventBus.server_created.emit()
	return true

## Local-only tester shortcut. It is intentionally not exposed as an RPC and
## therefore cannot be used to bypass ready/min-player checks on network tables.
func host_solo_test(ruleset_id: String = "") -> bool:
	if mode != Mode.NONE:
		disconnect_session()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.HOST
	_local_peer_id = 1
	_init_server_game(ruleset_id)
	game.add_player(1, GameConfig.to_join_payload())
	_broadcast_snapshot()
	_push_balance(1)
	EventBus.server_created.emit()
	return start_solo_test()

func start_solo_test() -> bool:
	if mode != Mode.HOST or game == null or not game.start_solo_test(1):
		return false
	_broadcast_snapshot()
	_broadcast_event(NetProtocol.EVENT_TURN, {
		"peer_id": game.current_peer(), "turn_phase": game.turn_phase})
	return true

func start_dedicated(port: int = DEFAULT_PORT, ruleset_id: String = "") -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_CLIENTS) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.DEDICATED
	_local_peer_id = 1
	_init_server_game(ruleset_id)
	EventBus.server_created.emit()
	print("[Net] Dedicated server listening on port %d" % port)
	return true

func join_game(host: String, port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(host, port) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	return true

func disconnect_session() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.NONE
	game = null
	local_snapshot = {}
	local_players = []
	local_board = null
	_local_board_ruleset = ""
	local_balance = 0
	local_private_state = {}
	_event_sequence = 0
	_last_received_event = 0

func _init_server_game(ruleset_id: String) -> void:
	game = GameController.new()
	var rid := ruleset_id if ruleset_id != "" else GameConfig.selected_ruleset
	game.configure(rid)

# --- Multiplayer signal handlers ----------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not is_server():
		return
	# Greet the newcomer with our pack signature so it can verify compatibility.
	rpc_id(id, "hello", PackRegistry.signature, ModLoader.get_pack_summaries(), ModLoader.API_VERSION)

func _on_peer_disconnected(id: int) -> void:
	if not is_server() or game == null:
		return
	game.remove_player(id)
	_broadcast_snapshot()

func _on_connected_to_server() -> void:
	_local_peer_id = multiplayer.get_unique_id()

func _on_connection_failed() -> void:
	mode = Mode.NONE
	EventBus.connection_failed.emit("Не удалось подключиться к серверу")

func _on_server_disconnected() -> void:
	var reason := last_disconnect_reason if last_disconnect_reason != "" else "Соединение с сервером потеряно"
	mode = Mode.NONE
	EventBus.connection_failed.emit(reason)

# --- Handshake RPCs -----------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func hello(server_signature: String, server_packs: Array, server_api: int) -> void:
	# Runs on the client. Verify our loaded packs match the server exactly.
	if server_api != ModLoader.API_VERSION or server_signature != PackRegistry.signature:
		var diff := _diff_packs(server_packs, ModLoader.get_pack_summaries())
		diff["server_api"] = server_api
		diff["client_api"] = ModLoader.API_VERSION
		last_disconnect_reason = "Рассинхрон паков/версий с сервером"
		EventBus.desync_detected.emit(diff)
		disconnect_session()
		return
	rpc_id(1, "submit_join", PackRegistry.signature, GameConfig.to_join_payload())
	EventBus.connection_succeeded.emit()

@rpc("any_peer", "call_remote", "reliable")
func submit_join(client_signature: String, join_payload: Dictionary) -> void:
	# Runs on the server.
	if not is_server() or game == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if client_signature != PackRegistry.signature:
		rpc_id(sender, "kicked", "Рассинхрон паков")
		multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	game.add_player(sender, join_payload)
	_broadcast_snapshot()
	_push_balance(sender)

@rpc("authority", "call_remote", "reliable")
func kicked(reason: String) -> void:
	last_disconnect_reason = reason
	EventBus.connection_failed.emit(reason)

# --- Gameplay RPCs ------------------------------------------------------------

func request_lobby_ready(ready: bool) -> void:
	if is_server():
		_server_set_ready(_effective_sender(1), ready)
	else:
		rpc_id(1, "server_request_ready", ready)

@rpc("any_peer", "call_remote", "reliable")
func server_request_ready(ready: bool) -> void:
	if is_server():
		_server_set_ready(multiplayer.get_remote_sender_id(), ready)

func _server_set_ready(sender: int, ready: bool) -> void:
	if game != null and game.set_ready(sender, ready):
		_broadcast_snapshot()

func request_profile_update() -> void:
	var payload := GameConfig.to_join_payload()
	if is_server():
		_server_update_profile(_effective_sender(1), payload)
	else:
		rpc_id(1, "server_update_profile", payload)

@rpc("any_peer", "call_remote", "reliable")
func server_update_profile(payload: Dictionary) -> void:
	if is_server():
		_server_update_profile(multiplayer.get_remote_sender_id(), payload)

func _server_update_profile(sender: int, payload: Dictionary) -> void:
	if game != null and game.update_player_profile(sender, payload):
		_broadcast_snapshot()

func request_start() -> void:
	if is_server():
		_server_start_game(_effective_sender(1))
	else:
		rpc_id(1, "server_request_start")

@rpc("any_peer", "call_remote", "reliable")
func server_request_start() -> void:
	if is_server():
		_server_start_game(multiplayer.get_remote_sender_id())

func _server_start_game(sender: int) -> void:
	if game == null:
		return
	if not game.start_game(sender):
		return
	_broadcast_snapshot()
	_broadcast_event(NetProtocol.EVENT_TURN, {"peer_id": game.current_peer()})

func request_roll() -> void:
	if is_server():
		_server_resolve_roll(_effective_sender(1))
	else:
		rpc_id(1, "server_request_roll")

@rpc("any_peer", "call_remote", "reliable")
func server_request_roll() -> void:
	if is_server():
		_server_resolve_roll(multiplayer.get_remote_sender_id())

func _server_resolve_roll(sender: int) -> void:
	var res := game.resolve_roll(sender)
	if res.is_empty():
		return
	_broadcast_event(NetProtocol.EVENT_ROLL, res)
	var action: Dictionary = res.get("action", {})
	if not action.is_empty():
		_broadcast_event(NetProtocol.EVENT_ACTION, {
			"name": str(action.get("type", "")), "data": action})
	_publish_result(res)

## On the host, a local UI action has no remote sender, so default to peer 1.
func _effective_sender(fallback: int) -> int:
	return fallback

func request_buy() -> void:
	if is_server():
		_publish_result(game.request_buy(_effective_sender(1)))
	else:
		rpc_id(1, "server_request_buy")

@rpc("any_peer", "call_remote", "reliable")
func server_request_buy() -> void:
	if is_server():
		_publish_result(game.request_buy(multiplayer.get_remote_sender_id()))

func request_decline_purchase() -> void:
	if is_server():
		_publish_result(game.request_decline_purchase(_effective_sender(1)))
	else:
		rpc_id(1, "server_request_decline_purchase")

@rpc("any_peer", "call_remote", "reliable")
func server_request_decline_purchase() -> void:
	if is_server():
		_publish_result(game.request_decline_purchase(multiplayer.get_remote_sender_id()))

func request_auction_bid(amount: int) -> void:
	if is_server():
		_publish_result(game.request_auction_bid(_effective_sender(1), amount))
	else:
		rpc_id(1, "server_request_auction_bid", amount)

@rpc("any_peer", "call_remote", "reliable")
func server_request_auction_bid(amount: int) -> void:
	if is_server():
		_publish_result(game.request_auction_bid(multiplayer.get_remote_sender_id(), amount))

func request_jail_action(action: String) -> void:
	if is_server():
		_publish_result(game.request_jail_action(_effective_sender(1), action))
	else:
		rpc_id(1, "server_request_jail_action", action)

@rpc("any_peer", "call_remote", "reliable")
func server_request_jail_action(action: String) -> void:
	if is_server():
		_publish_result(game.request_jail_action(multiplayer.get_remote_sender_id(), action))

func request_build(index: int) -> void:
	_send_index_action("build", index)

func request_sell_building(index: int) -> void:
	_send_index_action("sell_building", index)

func request_sell_property(index: int) -> void:
	_send_index_action("sell_property", index)

func request_mortgage(index: int) -> void:
	_send_index_action("mortgage", index)

func request_unmortgage(index: int) -> void:
	_send_index_action("unmortgage", index)

func _send_index_action(action: String, index: int) -> void:
	if is_server():
		_server_index_action(_effective_sender(1), action, index)
		return
	match action:
		"build": rpc_id(1, "server_request_build", index)
		"sell_building": rpc_id(1, "server_request_sell_building", index)
		"sell_property": rpc_id(1, "server_request_sell_property", index)
		"mortgage": rpc_id(1, "server_request_mortgage", index)
		"unmortgage": rpc_id(1, "server_request_unmortgage", index)

@rpc("any_peer", "call_remote", "reliable")
func server_request_build(index: int) -> void:
	_server_index_action(multiplayer.get_remote_sender_id(), "build", index)

@rpc("any_peer", "call_remote", "reliable")
func server_request_sell_building(index: int) -> void:
	_server_index_action(multiplayer.get_remote_sender_id(), "sell_building", index)

@rpc("any_peer", "call_remote", "reliable")
func server_request_sell_property(index: int) -> void:
	_server_index_action(multiplayer.get_remote_sender_id(), "sell_property", index)

@rpc("any_peer", "call_remote", "reliable")
func server_request_mortgage(index: int) -> void:
	_server_index_action(multiplayer.get_remote_sender_id(), "mortgage", index)

@rpc("any_peer", "call_remote", "reliable")
func server_request_unmortgage(index: int) -> void:
	_server_index_action(multiplayer.get_remote_sender_id(), "unmortgage", index)

func _server_index_action(sender: int, action: String, index: int) -> void:
	if not is_server() or game == null:
		return
	var result: Dictionary
	match action:
		"build": result = game.request_build(sender, index)
		"sell_building": result = game.request_sell_building(sender, index)
		"sell_property": result = game.request_sell_property(sender, index)
		"mortgage": result = game.request_mortgage(sender, index)
		"unmortgage": result = game.request_unmortgage(sender, index)
	_publish_result(result)

func request_bankruptcy() -> void:
	if is_server():
		_publish_result(game.request_bankruptcy(_effective_sender(1)))
	else:
		rpc_id(1, "server_request_bankruptcy")

@rpc("any_peer", "call_remote", "reliable")
func server_request_bankruptcy() -> void:
	if is_server():
		_publish_result(game.request_bankruptcy(multiplayer.get_remote_sender_id()))

func propose_trade(data: Dictionary) -> void:
	if is_server():
		_server_propose_trade(_effective_sender(1), data)
	else:
		rpc_id(1, "server_propose_trade", data)

@rpc("any_peer", "call_remote", "reliable")
func server_propose_trade(data: Dictionary) -> void:
	_server_propose_trade(multiplayer.get_remote_sender_id(), data)

func _server_propose_trade(sender: int, data: Dictionary) -> void:
	if not is_server() or game == null:
		return
	var result := game.propose_trade(sender, data)
	_publish_result(result)

func respond_trade(trade_id: int, accept: bool) -> void:
	if is_server():
		_publish_result(game.respond_trade(_effective_sender(1), trade_id, accept))
	else:
		rpc_id(1, "server_respond_trade", trade_id, accept)

@rpc("any_peer", "call_remote", "reliable")
func server_respond_trade(trade_id: int, accept: bool) -> void:
	if is_server():
		_publish_result(game.respond_trade(multiplayer.get_remote_sender_id(), trade_id, accept))

func _publish_result(result: Dictionary) -> void:
	if result.is_empty() or not bool(result.get("ok", true)):
		return
	_broadcast_snapshot()
	for peer in result.get("changed_peers", []):
		_push_balance(int(peer))
	var event_name := str(result.get("event", ""))
	if event_name != "":
		var public_data := result.duplicate(true)
		public_data.erase("trade")
		public_data.erase("amount")
		_broadcast_event(NetProtocol.EVENT_ACTION, {
			"name": event_name, "data": public_data})
	_broadcast_event(NetProtocol.EVENT_TURN, {
		"peer_id": game.current_peer(), "turn_phase": game.turn_phase})

# --- Server -> client state pushes --------------------------------------------

func _broadcast_snapshot() -> void:
	if game == null:
		return
	var snap := game.public_snapshot()
	rpc("receive_snapshot", snap)     # remotes
	if is_host():
		_apply_snapshot(snap)         # local host mirror
	for peer_id in game.players.keys():
		_push_private_state(int(peer_id))

func _broadcast_event(event_name: String, data: Dictionary) -> void:
	_event_sequence += 1
	var payload := data.duplicate(true)
	payload["event_sequence"] = _event_sequence
	payload["state_sequence"] = game.sequence if game != null else 0
	rpc("receive_event", event_name, payload)
	if is_host():
		_apply_event(event_name, payload)

func _push_balance(peer_id: int) -> void:
	if game == null:
		return
	var amount := game.ledger.get_balance(peer_id)
	if _is_local_player(peer_id):
		_set_local_balance(amount)
	else:
		rpc_id(peer_id, "receive_balance", amount)

func _push_private_state(peer_id: int) -> void:
	if game == null or not game.players.has(peer_id):
		return
	var state := game.private_state(peer_id)
	if _is_local_player(peer_id):
		_apply_private_state(state)
	elif multiplayer.get_peers().has(peer_id):
		rpc_id(peer_id, "receive_private_state", state)

@rpc("authority", "call_remote", "reliable")
func receive_snapshot(snapshot: Dictionary) -> void:
	_apply_snapshot(snapshot)

@rpc("authority", "call_remote", "reliable")
func receive_balance(amount: int) -> void:
	_set_local_balance(amount)

@rpc("authority", "call_remote", "reliable")
func receive_private_state(state: Dictionary) -> void:
	_apply_private_state(state)

@rpc("authority", "call_remote", "reliable")
func receive_event(event_name: String, data: Dictionary) -> void:
	_apply_event(event_name, data)

# --- Client mirror handling ---------------------------------------------------

func _apply_snapshot(snapshot: Dictionary) -> void:
	if int(snapshot.get("sequence", 0)) < int(local_snapshot.get("sequence", -1)):
		return
	local_snapshot = snapshot
	local_players.clear()
	for pdict in snapshot.get("players", []):
		local_players.append(PlayerState.from_public_dict(pdict))
	var ruleset_id := str(snapshot.get("ruleset_id", ""))
	if ruleset_id != "" and ruleset_id != _local_board_ruleset:
		var ruleset := PackRegistry.get_def("rulesets", ruleset_id)
		if not ruleset.is_empty():
			local_board = BoardModel.build(ruleset)
			_local_board_ruleset = ruleset_id
	EventBus.game_state_changed.emit(snapshot)

func _apply_private_state(state: Dictionary) -> void:
	if int(state.get("sequence", 0)) < int(local_private_state.get("sequence", -1)):
		return
	local_private_state = state
	_set_local_balance(int(state.get("balance", local_balance)))
	EventBus.private_state_changed.emit(state)

func _apply_event(event_name: String, data: Dictionary) -> void:
	var event_sequence := int(data.get("event_sequence", 0))
	if event_sequence > 0 and event_sequence <= _last_received_event:
		return
	_last_received_event = event_sequence
	match event_name:
		NetProtocol.EVENT_ROLL:
			EventBus.dice_rolled.emit(int(data.get("peer_id", 0)), data.get("dice", []))
			EventBus.player_moved.emit(
				int(data.get("peer_id", 0)),
				int(data.get("from_index", 0)),
				int(data.get("to_index", 0)))
		NetProtocol.EVENT_TURN:
			EventBus.turn_changed.emit(int(data.get("peer_id", 0)))
		NetProtocol.EVENT_ACTION:
			EventBus.game_action.emit(
				str(data.get("name", "")),
				data.get("data", {}))
		_:
			pass

func _set_local_balance(amount: int) -> void:
	local_balance = amount
	EventBus.local_balance_changed.emit(amount)

# --- Helpers ------------------------------------------------------------------

func get_local_peer_id() -> int:
	if mode == Mode.HOST:
		return 1
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 0

func is_local_turn() -> bool:
	return int(local_snapshot.get("current_peer", -1)) == get_local_peer_id()

func _diff_packs(server_packs: Array, client_packs: Array) -> Dictionary:
	var server_by_id: Dictionary = {}
	var client_by_id: Dictionary = {}
	for p in server_packs:
		server_by_id[str(p.get("id", ""))] = p
	for p in client_packs:
		client_by_id[str(p.get("id", ""))] = p
	var missing: Array = []          # server has, client lacks
	var extra: Array = []            # client has, server lacks
	var version_mismatch: Array = []
	for id in server_by_id:
		if not client_by_id.has(id):
			missing.append(server_by_id[id])
		elif str(server_by_id[id].get("version", "")) != str(client_by_id[id].get("version", "")):
			version_mismatch.append({
				"id": id,
				"server": server_by_id[id].get("version", ""),
				"client": client_by_id[id].get("version", ""),
			})
	for id in client_by_id:
		if not server_by_id.has(id):
			extra.append(client_by_id[id])
	return {"missing": missing, "extra": extra, "version_mismatch": version_mismatch}
