class_name BoardRenderer
extends Node3D
## Premium 2.5D board, token movement and physical dice feedback.

## World-unit footprint of one board cell. Bumped up from the original 1.0 so
## tiles are big enough to read their card (icon/name/price/rent ladder)
## instead of looking like a small block of overlapping text.
const TILE_SIZE := 1.6
## Extra space reserved beyond the outer ring of tiles for the property card's
## photo (the only part of the card that extends outward past the tile - the
## rent-ladder rows stack inward, into the board's empty interior instead).
## Exposed so GameScene can size the table/camera to match.
const CARD_MARGIN := TILE_SIZE * 1.4
const TOKEN_SCRIPT := preload("res://render/TokenView.gd")
const FELT_SHADER := preload("res://render/shaders/felt.gdshader")
const GOLD_SHADER := preload("res://render/shaders/gold.gdshader")

var _tiles_root: Node3D
var _tokens_root: Node3D
var _decor_root: Node3D
var _dice_root: Node3D
var _property_root: Node3D
var _tokens: Dictionary = {}
var _tile_meshes: Array[MeshInstance3D] = []
var _board: BoardModel
var _board_key := ""
var _current_peer := 0

func _ready() -> void:
	_decor_root = Node3D.new()
	_decor_root.name = "BoardFoundation"
	add_child(_decor_root)
	_tiles_root = Node3D.new()
	_tiles_root.name = "Tiles"
	add_child(_tiles_root)
	_tokens_root = Node3D.new()
	_tokens_root.name = "Tokens"
	add_child(_tokens_root)
	_dice_root = Node3D.new()
	_dice_root.name = "Dice"
	add_child(_dice_root)
	_property_root = Node3D.new()
	_property_root.name = "PropertyOverlays"
	add_child(_property_root)

	EventBus.game_state_changed.connect(_on_state_changed)
	EventBus.player_moved.connect(_on_player_moved)
	EventBus.turn_changed.connect(_on_turn_changed)
	EventBus.dice_rolled.connect(_on_dice_rolled)
	_current_peer = int(NetworkManager.local_snapshot.get("current_peer", 0))
	_refresh()

func _on_state_changed(snapshot: Dictionary) -> void:
	_current_peer = int(snapshot.get("current_peer", 0))
	_refresh()

func _refresh() -> void:
	var board := NetworkManager.local_board
	if board == null:
		return
	var board_key := "%d:%d" % [board.size, board.cell_count()]
	if _board_key != board_key:
		_board = board
		_board_key = board_key
		_build_board()
	_sync_tokens()
	_sync_property_overlays()

func _build_board() -> void:
	for root in [_decor_root, _tiles_root]:
		for child in root.get_children():
			child.queue_free()
	_tile_meshes.clear()
	_build_foundation()
	for index in _board.cell_count():
		_build_tile(index)
	_build_center_mark()

func _current_ruleset() -> Dictionary:
	return PackRegistry.get_def("rulesets", str(NetworkManager.local_snapshot.get("ruleset_id", "")))

func _build_foundation() -> void:
	var board_world_size := float(_board.size) * TILE_SIZE + CARD_MARGIN
	var ruleset := _current_ruleset()
	var custom := AssetLoader.instantiate_from_def(ruleset, "board_model")
	if custom != null:
		custom.scale = Vector3.ONE * board_world_size
		_decor_root.add_child(custom)
		return
	var slab := MeshInstance3D.new()
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(board_world_size, 0.22, board_world_size)
	slab.mesh = slab_mesh
	slab.position.y = -0.03
	var slab_material := ShaderMaterial.new()
	slab_material.shader = FELT_SHADER
	slab_material.set_shader_parameter("base_color", Color(0.95, 0.96, 0.98))
	slab_material.set_shader_parameter("fiber_color", Color(0.90, 0.92, 0.95))
	slab.material_override = slab_material
	_decor_root.add_child(slab)

	var gold := ShaderMaterial.new()
	gold.shader = GOLD_SHADER
	var half := board_world_size * 0.5
	_add_bar(_decor_root, Vector3(0, 0.115, -half), Vector3(board_world_size + 0.22, 0.07, 0.08), gold)
	_add_bar(_decor_root, Vector3(0, 0.115, half), Vector3(board_world_size + 0.22, 0.07, 0.08), gold)
	_add_bar(_decor_root, Vector3(-half, 0.115, 0), Vector3(0.08, 0.07, board_world_size + 0.22), gold)
	_add_bar(_decor_root, Vector3(half, 0.115, 0), Vector3(0.08, 0.07, board_world_size + 0.22), gold)

func _build_tile(index: int) -> void:
	var cell := _board.get_cell(index)
	var coord := _board.get_coord(index)
	var is_corner: bool = "corner" in cell.get("tags", [])
	var height := 0.30 if is_corner else 0.18
	var tile := MeshInstance3D.new()
	tile.name = "Tile_%02d" % index
	var mesh := BoxMesh.new()
	mesh.size = Vector3(TILE_SIZE * 0.92, height, TILE_SIZE * 0.92)
	tile.mesh = mesh
	tile.position = _world_pos(coord) + Vector3(0, 0.12 + height * 0.5, 0)

	var material := StandardMaterial3D.new()
	var accent := ColorUtil.to_color(cell.get("color", "#c7b998"))
	material.albedo_color = accent.lerp(Color("#eef1f5"), 0.72 if not is_corner else 0.35)
	material.roughness = 0.62
	material.metallic = 0.06
	tile.material_override = material
	_tiles_root.add_child(tile)
	_tile_meshes.append(tile)

	if str(cell.get("type", "")) == "property":
		_build_property_card(cell, coord, height)
	else:
		if not is_corner:
			_add_property_band(coord, accent, height)
		_add_tile_label(cell, coord, height, is_corner, index)
	_add_tile_decor(cell, coord, height)

func _label_rotation_y(coord: Vector2i) -> float:
	var last := _board.size - 1
	if coord.x == last:
		return 90.0
	if coord.x == 0:
		return -90.0
	return 0.0

## Builds a standalone "card" for a business cell: a photo/logo square
## (outermost, toward the board's edge) followed by bordered rows for the
## name, price and rent-per-ownership-tier ladder, stacked further outward.
## Positioned using the same edge_direction() the property band already uses,
## so it lines up correctly on every side of the board.
func _build_property_card(cell: Dictionary, coord: Vector2i, height: float) -> void:
	var edge := _edge_direction(coord)
	var rotation_y := _label_rotation_y(coord)
	var along_edge := absf(edge.x) > 0.5
	var base := _world_pos(coord)
	var lift := 0.12 + height

	var photo_offset := 0.30 * TILE_SIZE
	var photo_size := 0.36 * TILE_SIZE
	var photo_center := base + Vector3(edge.x * photo_offset, 0, edge.y * photo_offset)

	var backdrop := MeshInstance3D.new()
	var backdrop_mesh := BoxMesh.new()
	backdrop_mesh.size = Vector3(photo_size, 0.02, photo_size)
	backdrop.mesh = backdrop_mesh
	backdrop.position = photo_center + Vector3(0, lift + 0.01, 0)
	var backdrop_material := StandardMaterial3D.new()
	backdrop_material.albedo_color = ColorUtil.to_color(cell.get("color", "#70402b"))
	backdrop.material_override = backdrop_material
	_tiles_root.add_child(backdrop)

	var icon := Sprite3D.new()
	icon.texture = AssetLoader.texture_from_def(cell, "icon")
	if str(cell.get("icon", "")) == "":
		icon.modulate = ColorUtil.to_color(cell.get("color", "#c79b3b"))
	icon.pixel_size = (photo_size * 0.9) / maxf(float(icon.texture.get_width()), 1.0)
	icon.no_depth_test = true
	icon.render_priority = 1
	icon.rotation_degrees = Vector3(-90, rotation_y, 0)
	icon.position = photo_center + Vector3(0, lift + 0.03, 0)
	_tiles_root.add_child(icon)

	var rows: Array[String] = [str(cell.get("name", ""))]
	rows.append("%s $" % _format_amount(int(cell.get("price", 0))))
	for rent in GameRules.rent_ladder(cell, _board):
		rows.append(_format_amount(int(rent)))

	var row_depth := 0.13 * TILE_SIZE
	var row_gap := 0.02 * TILE_SIZE
	var cursor := photo_offset - photo_size * 0.5 - row_gap - row_depth * 0.5
	for row_text in rows:
		var center := base + Vector3(edge.x * cursor, 0, edge.y * cursor)
		_add_card_row(row_text, center, rotation_y, along_edge, row_depth, lift)
		cursor -= row_depth + row_gap

func _add_card_row(
		text: String, center: Vector3, rotation_y: float,
		along_edge: bool, depth: float, lift: float
) -> void:
	var width := 0.9 * TILE_SIZE
	var bar_size := Vector3(width, 0.03, depth)
	var inset := Vector3(0.05 * TILE_SIZE, 0, 0)
	if along_edge:
		bar_size = Vector3(depth, 0.03, width)
		inset = Vector3(0, 0, 0.05 * TILE_SIZE)

	var border := MeshInstance3D.new()
	var border_mesh := BoxMesh.new()
	border_mesh.size = bar_size
	border.mesh = border_mesh
	border.position = center + Vector3(0, lift + 0.01, 0)
	var border_material := StandardMaterial3D.new()
	border_material.albedo_color = Color("#c7cdd6")
	border.material_override = border_material
	_tiles_root.add_child(border)

	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = bar_size - inset * 2.0
	fill.mesh = fill_mesh
	fill.position = center + Vector3(0, lift + 0.018, 0)
	var fill_material := StandardMaterial3D.new()
	fill_material.albedo_color = Color("#ffffff")
	fill.material_override = fill_material
	_tiles_root.add_child(fill)

	var label := Label3D.new()
	label.text = text
	label.font_size = 44
	label.pixel_size = 0.0042 * TILE_SIZE
	label.modulate = Color("#1e2430")
	label.no_depth_test = true
	label.render_priority = 2
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.rotation_degrees = Vector3(-90, rotation_y, 0)
	label.position = center + Vector3(0, lift + 0.03, 0)
	_tiles_root.add_child(label)

func _add_tile_decor(cell: Dictionary, coord: Vector2i, height: float) -> void:
	var decor := AssetLoader.instantiate_from_def(cell, "decor_model")
	if decor == null:
		return
	decor.position = _world_pos(coord) + Vector3(0, 0.12 + height, 0)
	_tiles_root.add_child(decor)

func _add_property_band(coord: Vector2i, color: Color, height: float) -> void:
	var band := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.78, 0.025, 0.16) * TILE_SIZE
	band.mesh = mesh
	var edge := _edge_direction(coord)
	if absf(edge.x) > 0.5:
		mesh.size = Vector3(0.16, 0.025, 0.78) * TILE_SIZE
	band.position = _world_pos(coord) + Vector3(edge.x * 0.34 * TILE_SIZE, 0.12 + height + 0.016, edge.y * 0.34 * TILE_SIZE)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.42
	material.emission_enabled = true
	material.emission = color * 0.08
	band.material_override = material
	_tiles_root.add_child(band)

func _add_tile_label(cell: Dictionary, coord: Vector2i, height: float, is_corner: bool, index: int) -> void:
	var label := Label3D.new()
	var name := str(cell.get("name", ""))
	if not is_corner and name.length() > 13:
		var split := name.find(" ", 6)
		if split > 0:
			name = name.left(split) + "\n" + name.substr(split + 1)
		else:
			name = name.left(12) + "…"
	if GameRules.is_purchasable(cell):
		name += "\n%s $" % _format_amount(int(cell.get("price", 0)))
	var ladder := GameRules.rent_ladder(cell, _board)
	if not ladder.is_empty():
		var tiers: PackedStringArray = []
		for rent in ladder:
			tiers.append(_format_amount(int(rent)))
		name += "\n" + " · ".join(tiers)
	label.text = name
	label.font_size = 58 if is_corner else (44 if not ladder.is_empty() else 52)
	label.pixel_size = (0.0048 if is_corner else 0.0045) * TILE_SIZE
	label.modulate = Color("#1e2430")
	label.outline_size = 10
	label.outline_modulate = Color(1.0, 1.0, 1.0, 0.96)
	label.render_priority = 2
	label.no_depth_test = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rotation_y := 0.0
	var last := _board.size - 1
	if coord.x == last:
		rotation_y = 90.0
	elif coord.x == 0:
		rotation_y = -90.0
	label.rotation_degrees = Vector3(-90, rotation_y, 0)
	label.position = _world_pos(coord) + Vector3(0, 0.12 + height + 0.035, 0)
	_tiles_root.add_child(label)

func _build_center_mark() -> void:
	if _current_ruleset().has("board_model"):
		return # A custom board model is expected to include its own centerpiece.
	var seal := MeshInstance3D.new()
	var seal_mesh := CylinderMesh.new()
	seal_mesh.top_radius = 2.55
	seal_mesh.bottom_radius = 2.62
	seal_mesh.height = 0.045
	seal.mesh = seal_mesh
	seal.position.y = 0.12
	var seal_material := StandardMaterial3D.new()
	seal_material.albedo_color = Color("#2a3550")
	seal_material.roughness = 0.76
	seal_material.metallic = 0.12
	seal.material_override = seal_material
	_decor_root.add_child(seal)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.39
	torus.outer_radius = 2.48
	ring.mesh = torus
	ring.position.y = 0.17
	var gold := ShaderMaterial.new()
	gold.shader = GOLD_SHADER
	ring.material_override = gold
	_decor_root.add_child(ring)

	var logo := Label3D.new()
	logo.text = "M O N O P O L I S"
	logo.font_size = 68
	logo.pixel_size = 0.008
	logo.modulate = Color("#e6c66e")
	logo.outline_size = 8
	logo.outline_modulate = Color("#2c170d")
	logo.rotation_degrees = Vector3(-90, 0, 0)
	logo.position = Vector3(0, 0.19, 0)
	_decor_root.add_child(logo)

func _sync_tokens() -> void:
	var seen: Dictionary = {}
	for player in NetworkManager.local_players:
		seen[player.peer_id] = true
		var token: TokenView
		if _tokens.has(player.peer_id):
			token = _tokens[player.peer_id]
		else:
			token = TOKEN_SCRIPT.new()
			token.peer_id = player.peer_id
			_tokens_root.add_child(token)
			_tokens[player.peer_id] = token
		var token_def := PackRegistry.get_def("tokens", player.token_id)
		if token_def.is_empty():
			var all := PackRegistry.get_all("tokens")
			token_def = all[0] if not all.is_empty() else {}
		token.setup(token_def, player.customization)
		token.position = _token_world_pos(player.board_index, player.order)
		token.set_highlighted(player.peer_id == _current_peer)
	for peer in _tokens.keys():
		if not seen.has(peer):
			_tokens[peer].queue_free()
			_tokens.erase(peer)

func _sync_property_overlays() -> void:
	for child in _property_root.get_children():
		child.queue_free()
	for state_value in NetworkManager.local_snapshot.get("properties", []):
		var state: Dictionary = state_value
		var owner := int(state.get("owner_peer", 0))
		if owner == 0:
			continue
		var index := int(state.get("index", -1))
		if index < 0 or index >= _board.cell_count():
			continue
		var base := _world_pos(_board.get_coord(index))
		var owner_mark := MeshInstance3D.new()
		var mark_mesh := CylinderMesh.new()
		mark_mesh.top_radius = 0.09
		mark_mesh.bottom_radius = 0.11
		mark_mesh.height = 0.10
		owner_mark.mesh = mark_mesh
		owner_mark.position = base + Vector3(0.27 * TILE_SIZE, 0.49, -0.27 * TILE_SIZE)
		var owner_material := StandardMaterial3D.new()
		owner_material.albedo_color = _peer_color(owner)
		owner_material.emission_enabled = true
		owner_material.emission = owner_material.albedo_color * 0.18
		owner_mark.material_override = owner_material
		_property_root.add_child(owner_mark)
		var level := int(state.get("improvements", 0))
		for building_index in mini(level, 4):
			var house := MeshInstance3D.new()
			var house_mesh := BoxMesh.new()
			house_mesh.size = Vector3(0.11, 0.15, 0.11)
			house.mesh = house_mesh
			house.position = base + Vector3((-0.25 + building_index * 0.16) * TILE_SIZE, 0.51, 0.25 * TILE_SIZE)
			var house_material := StandardMaterial3D.new()
			house_material.albedo_color = Color("#277b4d")
			house.material_override = house_material
			_property_root.add_child(house)
		if level == 5:
			var hotel := MeshInstance3D.new()
			var hotel_mesh := BoxMesh.new()
			hotel_mesh.size = Vector3(0.34, 0.24, 0.16)
			hotel.mesh = hotel_mesh
			hotel.position = base + Vector3(0, 0.56, 0.25 * TILE_SIZE)
			var hotel_material := StandardMaterial3D.new()
			hotel_material.albedo_color = Color("#9d342e")
			hotel.material_override = hotel_material
			_property_root.add_child(hotel)
		if bool(state.get("mortgaged", false)):
			var mortgage := Label3D.new()
			mortgage.text = "ЗАЛОГ"
			mortgage.font_size = 36
			mortgage.pixel_size = 0.0048
			mortgage.modulate = Color("#9b2525")
			mortgage.outline_size = 6
			mortgage.rotation_degrees = Vector3(-90, 0, 0)
			mortgage.position = base + Vector3(0, 0.55, 0)
			_property_root.add_child(mortgage)

func _on_player_moved(peer_id: int, from_index: int, to_index: int) -> void:
	if not _tokens.has(peer_id) or _board == null:
		return
	var token: TokenView = _tokens[peer_id]
	var order := _order_of(peer_id)
	var count := _board.cell_count()
	var forward := posmod(to_index - from_index, count)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	var duration := 0.11 if not GameConfig.reduced_motion else 0.02
	if forward >= 1 and forward <= 12:
		for step in range(1, forward + 1):
			var target_index := (from_index + step) % count
			var target := _token_world_pos(target_index, order)
			tween.tween_property(token, "position", target + Vector3(0, 0.32, 0), duration * 0.46)
			tween.tween_property(token, "position", target, duration * 0.54)
	else:
		var target := _token_world_pos(to_index, order)
		tween.tween_property(token, "position", target + Vector3(0, 0.8, 0), 0.18)
		tween.tween_property(token, "position", target, 0.22).set_trans(Tween.TRANS_BACK)
	tween.finished.connect(func(): _pulse_tile(to_index))

func _on_turn_changed(peer_id: int) -> void:
	_current_peer = peer_id
	for peer in _tokens.keys():
		_tokens[peer].set_highlighted(peer == peer_id)

func _on_dice_rolled(_peer_id: int, values: Array) -> void:
	for child in _dice_root.get_children():
		child.queue_free()
	if not values.is_empty():
		var die := _make_die(int(values[0]))
		die.position = Vector3(0, 1.5, 0)
		die.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		_dice_root.add_child(die)
		var target := Vector3(0, 0.42, 0)
		var tween := create_tween().set_parallel(true)
		tween.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tween.tween_property(die, "position", target, 0.55)
		tween.tween_property(die, "rotation", Vector3(0.12, 0.18, -0.1), 0.55)

func _make_die(value: int) -> Node3D:
	var root := Node3D.new()
	var custom := AssetLoader.instantiate_from_def(_current_ruleset(), "dice_model")
	if custom != null:
		root.add_child(custom)
	else:
		var body := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * 0.58
		body.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#eee4cc")
		material.roughness = 0.42
		body.material_override = material
		root.add_child(body)
	var label := Label3D.new()
	label.text = str(value)
	label.font_size = 80
	label.pixel_size = 0.004
	label.modulate = Color("#301710")
	label.outline_size = 0
	label.position = Vector3(0, 0, 0.296)
	root.add_child(label)
	return root

func _pulse_tile(index: int) -> void:
	if index < 0 or index >= _tile_meshes.size() or GameConfig.reduced_motion:
		return
	var tile := _tile_meshes[index]
	if not is_instance_valid(tile):
		return
	var base_scale := tile.scale
	var tween := create_tween()
	tween.tween_property(tile, "scale", base_scale * 1.08, 0.12).set_trans(Tween.TRANS_BACK)
	tween.tween_property(tile, "scale", base_scale, 0.22)

func _order_of(peer_id: int) -> int:
	for player in NetworkManager.local_players:
		if player.peer_id == peer_id:
			return player.order
	return 0

func _token_world_pos(index: int, order: int) -> Vector3:
	var base := _world_pos(_board.get_coord(index))
	var offset := Vector3(((order % 2) * 0.32) - 0.16, 0, ((order / 2) * 0.32) - 0.16) * TILE_SIZE
	return base + offset + Vector3(0, 0.62, 0)

func _edge_direction(coord: Vector2i) -> Vector2:
	var last := _board.size - 1
	if coord.y == 0:
		return Vector2(0, 1)
	if coord.x == last:
		return Vector2(-1, 0)
	if coord.y == last:
		return Vector2(0, -1)
	return Vector2(1, 0)

func _world_pos(coord: Vector2i) -> Vector3:
	var half := (_board.size - 1) / 2.0
	return Vector3((coord.x - half) * TILE_SIZE, 0, (coord.y - half) * TILE_SIZE)

func _peer_color(peer_id: int) -> Color:
	var palette := [
		Color("#d44d46"), Color("#4787c7"), Color("#d1a441"), Color("#49a36e"),
		Color("#8d5bb5"), Color("#d27a3e"), Color("#5aa9a4"), Color("#d05d91")]
	return palette[absi(peer_id) % palette.size()]

func _format_amount(value: int) -> String:
	var text := str(absi(value))
	var output := ""
	while text.length() > 3:
		output = " " + text.right(3) + output
		text = text.left(text.length() - 3)
	return text + output

func _add_bar(parent: Node3D, position: Vector3, size: Vector3, material: Material) -> void:
	var bar := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	bar.mesh = mesh
	bar.position = position
	bar.material_override = material
	parent.add_child(bar)
