class_name PropertyState
extends RefCounted
## Public runtime state for a purchasable board cell.

var index := -1
var cell_id := ""
var owner_peer := 0
## 0 = none, 1..4 = houses, 5 = hotel.
var improvements := 0
var mortgaged := false

func to_dict() -> Dictionary:
	return {
		"index": index,
		"cell_id": cell_id,
		"owner_peer": owner_peer,
		"improvements": improvements,
		"mortgaged": mortgaged,
	}

static func from_dict(data: Dictionary) -> PropertyState:
	var state := PropertyState.new()
	state.index = int(data.get("index", -1))
	state.cell_id = str(data.get("cell_id", ""))
	state.owner_peer = int(data.get("owner_peer", 0))
	state.improvements = clampi(int(data.get("improvements", 0)), 0, 5)
	state.mortgaged = bool(data.get("mortgaged", false))
	return state
