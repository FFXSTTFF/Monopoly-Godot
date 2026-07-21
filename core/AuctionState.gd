class_name AuctionState
extends RefCounted
## Server-only sealed-bid auction. Bid amounts never enter public snapshots.

var property_index := -1
var participants: Array[int] = []
var bids: Dictionary = {}
var passed: Dictionary = {}
var active := false

func begin(index: int, peers: Array[int]) -> void:
	property_index = index
	participants = peers.duplicate()
	bids.clear()
	passed.clear()
	active = true

func submit(peer_id: int, amount: int) -> bool:
	if not active or not participants.has(peer_id) or bids.has(peer_id) or passed.has(peer_id):
		return false
	if amount <= 0:
		passed[peer_id] = true
	else:
		bids[peer_id] = amount
	return true

func all_responded() -> bool:
	return bids.size() + passed.size() >= participants.size()

func resolve() -> Dictionary:
	active = false
	var winner := 0
	var winning_bid := 0
	for peer_id in participants:
		var amount := int(bids.get(peer_id, 0))
		if amount > winning_bid:
			winning_bid = amount
			winner = peer_id
	return {"winner": winner, "amount": winning_bid, "property_index": property_index}

func public_dict() -> Dictionary:
	return {
		"active": active,
		"property_index": property_index,
		"participants": participants.duplicate(),
		"responded": bids.size() + passed.size(),
		"total": participants.size(),
	}
