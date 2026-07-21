class_name GameRules
extends RefCounted
## Pure validation/calculation helpers shared by the authoritative controller.

const PURCHASABLE_TYPES := ["property", "railroad", "utility"]

static func is_purchasable(cell: Dictionary) -> bool:
	return str(cell.get("type", "")) in PURCHASABLE_TYPES

static func price(cell: Dictionary) -> int:
	return maxi(0, int(cell.get("price", 0)))

static func mortgage_value(cell: Dictionary) -> int:
	return maxi(0, int(cell.get("mortgage", price(cell) / 2)))

static func sale_value(cell: Dictionary, multiplier: float = 0.5) -> int:
	return maxi(0, int(cell.get("sale_price", roundi(price(cell) * multiplier))))

static func group_indices(board: BoardModel, group_id: String) -> Array[int]:
	var indices: Array[int] = []
	if group_id == "":
		return indices
	for index in board.cell_count():
		if str(board.get_cell(index).get("group", "")) == group_id:
			indices.append(index)
	return indices

static func owns_group(
		peer_id: int,
		board: BoardModel,
		states: Dictionary,
		group_id: String
) -> bool:
	var indices := group_indices(board, group_id)
	if indices.is_empty():
		return false
	for index in indices:
		if not states.has(index) or states[index].owner_peer != peer_id:
			return false
	return true

static func group_owned_count(
		peer_id: int,
		board: BoardModel,
		states: Dictionary,
		group_id: String
) -> int:
	if group_id == "":
		return 0
	var count := 0
	for index in group_indices(board, group_id):
		if states.has(index) and states[index].owner_peer == peer_id:
			count += 1
	return count

## Rent scaling factor for owning `owned_count` properties of a group, before
## any houses are built. Grows smoothly with each additional property of the
## same group the owner picks up, tuned per-cell via "rent_growth" (e.g. 1.1 =
## +10% per additional property owned), instead of a single lump bonus that
## only triggers once the whole group is bought out.
static func rent_growth_multiplier(cell: Dictionary, owned_count: int) -> float:
	if owned_count <= 1:
		return 1.0
	var growth := float(cell.get("rent_growth", 1.0))
	return pow(growth, owned_count - 1)

## Preview rent at every ownership tier (1..group size) for this property's
## group, using its base rent and "rent_growth" - independent of the current
## game state. Used to print the rent ladder on the board tile.
static func rent_ladder(cell: Dictionary, board: BoardModel) -> Array:
	if str(cell.get("type", "")) != "property":
		return []
	var group_size := group_indices(board, str(cell.get("group", ""))).size()
	if group_size <= 1:
		return []
	var rents: Array = cell.get("rent_table", [int(cell.get("rent", 0))])
	var base := int(rents[0]) if not rents.is_empty() else 0
	var ladder: Array = []
	for owned in range(1, group_size + 1):
		ladder.append(int(round(base * rent_growth_multiplier(cell, owned))))
	return ladder

static func calculate_rent(
		cell: Dictionary,
		state: PropertyState,
		board: BoardModel,
		states: Dictionary,
		dice_value: int
) -> int:
	if state.mortgaged or state.owner_peer == 0:
		return 0
	var type := str(cell.get("type", ""))
	if type == "railroad":
		var count := 0
		for candidate_value in states.values():
			var candidate: PropertyState = candidate_value
			var candidate_cell := board.get_cell(candidate.index)
			if candidate.owner_peer == state.owner_peer and str(candidate_cell.get("type", "")) == "railroad":
				count += 1
		var rents: Array = cell.get("rent_table", [25000, 50000, 100000, 200000])
		return int(rents[clampi(count - 1, 0, rents.size() - 1)])
	if type == "utility":
		var owned := 0
		for candidate_value in states.values():
			var candidate: PropertyState = candidate_value
			var candidate_cell := board.get_cell(candidate.index)
			if candidate.owner_peer == state.owner_peer and str(candidate_cell.get("type", "")) == "utility":
				owned += 1
		return dice_value * int(cell.get("multiplier_two", 10000) if owned >= 2 else cell.get("multiplier_one", 4000))
	var rents: Array = cell.get("rent_table", [int(cell.get("rent", 0))])
	var level := clampi(state.improvements, 0, rents.size() - 1)
	var rent := int(rents[level])
	if level == 0:
		var owned := group_owned_count(state.owner_peer, board, states, str(cell.get("group", "")))
		rent = int(round(rent * rent_growth_multiplier(cell, owned)))
	return rent

static func can_build(
		peer_id: int,
		index: int,
		board: BoardModel,
		states: Dictionary
) -> bool:
	if not states.has(index):
		return false
	var state: PropertyState = states[index]
	var cell := board.get_cell(index)
	var group := str(cell.get("group", ""))
	if str(cell.get("type", "")) != "property" or state.owner_peer != peer_id:
		return false
	if state.mortgaged or state.improvements >= 5 or not owns_group(peer_id, board, states, group):
		return false
	var group_cells := group_indices(board, group)
	for group_index in group_cells:
		var other: PropertyState = states[group_index]
		if other.mortgaged or other.improvements < state.improvements:
			return false
	return true

static func can_sell_building(index: int, board: BoardModel, states: Dictionary) -> bool:
	if not states.has(index):
		return false
	var state: PropertyState = states[index]
	if state.improvements <= 0:
		return false
	var group := str(board.get_cell(index).get("group", ""))
	for group_index in group_indices(board, group):
		var other: PropertyState = states[group_index]
		if other.improvements > state.improvements:
			return false
	return true

static func group_has_buildings(index: int, board: BoardModel, states: Dictionary) -> bool:
	var group := str(board.get_cell(index).get("group", ""))
	for group_index in group_indices(board, group):
		if states.has(group_index) and states[group_index].improvements > 0:
			return true
	return false
