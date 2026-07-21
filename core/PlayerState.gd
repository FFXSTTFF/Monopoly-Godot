class_name PlayerState
extends RefCounted
## Per-player state that is safe to replicate to everyone.
## NOTE: balance is deliberately NOT stored here. Money lives only in the
## server-side MoneyLedger and is sent privately to its owner.

var peer_id: int = 0
var display_name: String = "Player"
var token_id: String = "core:token_hat"
var customization: Dictionary = {}
var role_id: String = "core:normal"
var board_index: int = 0
var in_jail: bool = false
var jail_turns: int = 0
var get_out_cards: int = 0
var ready: bool = false
var bankrupt: bool = false
var connected: bool = true
## Turn order slot, assigned by the server.
var order: int = 0

func to_public_dict() -> Dictionary:
	## Everything here is broadcast to all clients. No money.
	return {
		"peer_id": peer_id,
		"name": display_name,
		"token_id": token_id,
		"customization": customization,
		"role_id": role_id,
		"board_index": board_index,
		"in_jail": in_jail,
		"jail_turns": jail_turns,
		"ready": ready,
		"bankrupt": bankrupt,
		"connected": connected,
		"order": order,
	}

static func from_public_dict(data: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.peer_id = int(data.get("peer_id", 0))
	p.display_name = str(data.get("name", "Player"))
	p.token_id = str(data.get("token_id", "core:token_hat"))
	p.customization = data.get("customization", {})
	p.role_id = str(data.get("role_id", "core:normal"))
	p.board_index = int(data.get("board_index", 0))
	p.in_jail = bool(data.get("in_jail", false))
	p.jail_turns = int(data.get("jail_turns", 0))
	p.ready = bool(data.get("ready", false))
	p.bankrupt = bool(data.get("bankrupt", false))
	p.connected = bool(data.get("connected", true))
	p.order = int(data.get("order", 0))
	return p
