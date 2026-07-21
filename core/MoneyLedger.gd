class_name MoneyLedger
extends RefCounted
## Server-only balance store.
##
## The whole point of the game is that money is hidden: a client only ever
## learns its OWN balance. This object must never leave the server, and its
## values are pushed to owners one-by-one via a private RPC.

## peer_id -> int balance
var _balances: Dictionary = {}

func add_player(peer_id: int, starting_cash: int) -> void:
	_balances[peer_id] = starting_cash

func remove_player(peer_id: int) -> void:
	_balances.erase(peer_id)

func has_player(peer_id: int) -> bool:
	return _balances.has(peer_id)

func get_balance(peer_id: int) -> int:
	return int(_balances.get(peer_id, 0))

func can_afford(peer_id: int, amount: int) -> bool:
	return amount >= 0 and get_balance(peer_id) >= amount

func credit(peer_id: int, amount: int) -> void:
	if _balances.has(peer_id) and amount > 0:
		_balances[peer_id] += amount

## Exact debit. Returns false instead of silently erasing an unpaid debt.
func debit(peer_id: int, amount: int) -> bool:
	if not can_afford(peer_id, amount):
		return false
	_balances[peer_id] -= amount
	return true

func transfer(from_peer: int, to_peer: int, amount: int) -> bool:
	if not debit(from_peer, amount):
		return false
	credit(to_peer, amount)
	return true

func set_balance(peer_id: int, amount: int) -> void:
	if _balances.has(peer_id):
		_balances[peer_id] = maxi(0, amount)

func all_peers() -> Array:
	return _balances.keys()
