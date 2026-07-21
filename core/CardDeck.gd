class_name CardDeck
extends RefCounted
## Server-only shuffled deck. Definitions remain data-driven pack content.

var deck_id := ""
var _cards: Array[Dictionary] = []
var _draw_order: Array[int] = []
var _cursor := 0
var _rng := RandomNumberGenerator.new()

func setup(id: String, definitions: Array, seed: int = 0) -> void:
	deck_id = id
	_cards.clear()
	for definition in definitions:
		if str(definition.get("deck", "")) == id:
			_cards.append(definition.duplicate(true))
	_rng.seed = seed if seed != 0 else Time.get_ticks_usec()
	_reshuffle()

func draw() -> Dictionary:
	if _cards.is_empty():
		return {}
	if _cursor >= _draw_order.size():
		_reshuffle()
	var card := _cards[_draw_order[_cursor]].duplicate(true)
	_cursor += 1
	return card

func _reshuffle() -> void:
	_draw_order.clear()
	for index in _cards.size():
		_draw_order.append(index)
	for index in range(_draw_order.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary := _draw_order[index]
		_draw_order[index] = _draw_order[swap_index]
		_draw_order[swap_index] = temporary
	_cursor = 0
