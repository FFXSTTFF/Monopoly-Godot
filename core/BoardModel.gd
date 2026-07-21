class_name BoardModel
extends RefCounted
## Ring board built from a ruleset definition.
##
## A size*size grid where only the outer edge is playable. For size 15 that is
## 15*4 - 4 = 56 cells laid out clockwise starting at the top-left corner.

var size: int = 15
## Ring-ordered array of cell definition Dictionaries (from PackRegistry).
var cells: Array = []
## Ring-ordered grid coordinates (Vector2i) parallel to `cells`.
var coords: Array[Vector2i] = []
var start_index: int = 0
var jail_index: int = -1

func cell_count() -> int:
	return cells.size()

func get_cell(index: int) -> Dictionary:
	if cells.is_empty():
		return {}
	return cells[posmod(index, cells.size())]

func get_coord(index: int) -> Vector2i:
	if coords.is_empty():
		return Vector2i.ZERO
	return coords[posmod(index, coords.size())]

## Builds the board from a ruleset def. Missing/invalid cell refs fall back to
## the ruleset's default_cell so a broken pack cannot crash the board.
static func build(ruleset: Dictionary) -> BoardModel:
	var model := BoardModel.new()
	model.size = int(ruleset.get("board_size", 15))
	model.coords = _perimeter_coords(model.size)

	var default_id: String = str(ruleset.get("default_cell", ""))
	var special: Dictionary = ruleset.get("special_cells", {})
	var board_cells: Array = ruleset.get("board_cells", [])

	var count := model.coords.size()
	for i in count:
		var cell_id: String = default_id
		if i < board_cells.size():
			cell_id = str(board_cells[i])
		var key := str(i)
		if board_cells.is_empty() and special.has(key):
			cell_id = str(special[key])
		var def := PackRegistry.get_def("cells", cell_id)
		if def.is_empty():
			def = PackRegistry.get_def("cells", default_id)
		model.cells.append(def.duplicate(true))
		var cell_type := str(def.get("type", ""))
		if cell_type == "corner_start":
			model.start_index = i
		elif cell_type == "corner_jail":
			model.jail_index = i
	return model

## Clockwise perimeter coordinates starting at (0,0):
## top edge -> right edge -> bottom edge -> left edge.
static func _perimeter_coords(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if n < 2:
		out.append(Vector2i.ZERO)
		return out
	var last := n - 1
	for x in range(0, n):        # top, left -> right
		out.append(Vector2i(x, 0))
	for y in range(1, n):        # right, top -> bottom
		out.append(Vector2i(last, y))
	for x in range(last - 1, -1, -1):  # bottom, right -> left
		out.append(Vector2i(x, last))
	for y in range(last - 1, 0, -1):   # left, bottom -> top
		out.append(Vector2i(0, y))
	return out
