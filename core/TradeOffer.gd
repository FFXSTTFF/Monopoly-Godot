class_name TradeOffer
extends RefCounted
## Server-side private offer. Full terms are sent only to both participants.

var trade_id := 0
var from_peer := 0
var to_peer := 0
var offer_cash := 0
var request_cash := 0
var offer_properties: Array[int] = []
var request_properties: Array[int] = []
var offer_cards := 0
var request_cards := 0
var state := "proposed"

func setup(id: int, sender: int, receiver: int, data: Dictionary) -> void:
	trade_id = id
	from_peer = sender
	to_peer = receiver
	offer_cash = maxi(0, int(data.get("offer_cash", 0)))
	request_cash = maxi(0, int(data.get("request_cash", 0)))
	offer_properties = _int_array(data.get("offer_properties", []))
	request_properties = _int_array(data.get("request_properties", []))
	offer_cards = maxi(0, int(data.get("offer_cards", 0)))
	request_cards = maxi(0, int(data.get("request_cards", 0)))

func involves(peer_id: int) -> bool:
	return peer_id == from_peer or peer_id == to_peer

func to_private_dict() -> Dictionary:
	return {
		"trade_id": trade_id,
		"from_peer": from_peer,
		"to_peer": to_peer,
		"offer_cash": offer_cash,
		"request_cash": request_cash,
		"offer_properties": offer_properties.duplicate(),
		"request_properties": request_properties.duplicate(),
		"offer_cards": offer_cards,
		"request_cards": request_cards,
		"state": state,
	}

static func _int_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		var parsed := int(value)
		if not result.has(parsed):
			result.append(parsed)
		if result.size() >= 64:
			break
	return result
