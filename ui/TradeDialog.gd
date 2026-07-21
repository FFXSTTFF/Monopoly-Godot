class_name TradeDialog
extends Control
## Private bilateral trade UI. Terms are never broadcast to spectators.

var incoming_trade: Dictionary = {}
var _target: OptionButton
var _target_peers: Array[int] = []
var _offer_cash: SpinBox
var _request_cash: SpinBox
var _own_list: ItemList
var _their_list: ItemList
var _own_indices: Array[int] = []
var _their_indices: Array[int] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = LuxuryTheme.create()
	_build()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 620)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	var title := Label.new()
	title.text = "Входящее предложение" if not incoming_trade.is_empty() else "Приватная сделка"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiPalette.GOLD_LIGHT)
	root.add_child(title)
	if not incoming_trade.is_empty():
		_build_incoming(root)
	else:
		_build_proposal(root)

func _build_proposal(root: VBoxContainer) -> void:
	var target_row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Партнёр"
	label.custom_minimum_size.x = 150
	target_row.add_child(label)
	_target = OptionButton.new()
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var me := NetworkManager.get_local_peer_id()
	for player in NetworkManager.local_players:
		if player.peer_id != me and not player.bankrupt:
			_target_peers.append(player.peer_id)
			_target.add_item(player.display_name)
	_target.item_selected.connect(func(_index: int): _rebuild_their_properties())
	target_row.add_child(_target)
	root.add_child(target_row)

	var money := HBoxContainer.new()
	_offer_cash = _spinbox(NetworkManager.local_balance)
	_request_cash = _spinbox(5000000)
	money.add_child(_label_with_width("Вы предлагаете", 150))
	money.add_child(_offer_cash)
	money.add_child(_label_with_width("Запрашиваете", 150))
	money.add_child(_request_cash)
	root.add_child(money)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	var own := VBoxContainer.new()
	own.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	own.add_child(_caption("ВАША СОБСТВЕННОСТЬ"))
	_own_list = _property_list()
	own.add_child(_own_list)
	columns.add_child(own)
	var theirs := VBoxContainer.new()
	theirs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theirs.add_child(_caption("СОБСТВЕННОСТЬ ПАРТНЁРА"))
	_their_list = _property_list()
	theirs.add_child(_their_list)
	columns.add_child(theirs)
	root.add_child(columns)
	_rebuild_own_properties()
	_rebuild_their_properties()

	var buttons := HBoxContainer.new()
	var cancel := Button.new()
	cancel.text = "Отмена"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(queue_free)
	buttons.add_child(cancel)
	var send := Button.new()
	send.text = "ОТПРАВИТЬ ПРЕДЛОЖЕНИЕ"
	send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send.pressed.connect(_send)
	buttons.add_child(send)
	root.add_child(buttons)

func _build_incoming(root: VBoxContainer) -> void:
	var from_peer := int(incoming_trade.get("from_peer", 0))
	var summary := Label.new()
	summary.text = "%s предлагает:\n• %s $\n• %s\n\nВ обмен на:\n• %s $\n• %s" % [
		_name_of(from_peer),
		_money(int(incoming_trade.get("offer_cash", 0))),
		_property_names(incoming_trade.get("offer_properties", [])),
		_money(int(incoming_trade.get("request_cash", 0))),
		_property_names(incoming_trade.get("request_properties", []))]
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 19)
	root.add_child(summary)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)
	var buttons := HBoxContainer.new()
	var reject := Button.new()
	reject.text = "ОТКЛОНИТЬ"
	reject.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reject.pressed.connect(func():
		NetworkManager.respond_trade(int(incoming_trade.get("trade_id", 0)), false)
		queue_free())
	buttons.add_child(reject)
	var accept := Button.new()
	accept.text = "ПРИНЯТЬ СДЕЛКУ"
	accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept.pressed.connect(func():
		NetworkManager.respond_trade(int(incoming_trade.get("trade_id", 0)), true)
		queue_free())
	buttons.add_child(accept)
	root.add_child(buttons)

func _send() -> void:
	if _target_peers.is_empty():
		return
	NetworkManager.propose_trade({
		"to_peer": _target_peers[_target.selected],
		"offer_cash": int(_offer_cash.value),
		"request_cash": int(_request_cash.value),
		"offer_properties": _selected_indices(_own_list, _own_indices),
		"request_properties": _selected_indices(_their_list, _their_indices),
	})
	queue_free()

func _rebuild_own_properties() -> void:
	_fill_properties(_own_list, _own_indices, NetworkManager.get_local_peer_id())

func _rebuild_their_properties() -> void:
	if _target == null or _target_peers.is_empty():
		return
	_fill_properties(_their_list, _their_indices, _target_peers[_target.selected])

func _fill_properties(list: ItemList, indices: Array[int], owner: int) -> void:
	list.clear()
	indices.clear()
	for state_value in NetworkManager.local_snapshot.get("properties", []):
		var state: Dictionary = state_value
		if int(state.get("owner_peer", 0)) != owner or int(state.get("improvements", 0)) > 0:
			continue
		var index := int(state.get("index", -1))
		indices.append(index)
		list.add_item(str(NetworkManager.local_board.get_cell(index).get("name", "?")))

func _property_list() -> ItemList:
	var list := ItemList.new()
	list.select_mode = ItemList.SELECT_MULTI
	list.custom_minimum_size = Vector2(0, 300)
	return list

func _selected_indices(list: ItemList, source: Array[int]) -> Array[int]:
	var result: Array[int] = []
	for selected in list.get_selected_items():
		if selected >= 0 and selected < source.size():
			result.append(source[selected])
	return result

func _property_names(indices: Array) -> String:
	if indices.is_empty():
		return "без собственности"
	var names: Array[String] = []
	for index_value in indices:
		var index := int(index_value)
		names.append(str(NetworkManager.local_board.get_cell(index).get("name", "?")))
	return ", ".join(names)

func _spinbox(maximum: int) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = 0
	box.max_value = maximum
	box.step = 10000
	box.custom_minimum_size.x = 160
	box.suffix = " $"
	return box

func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", UiPalette.GOLD)
	return label

func _label_with_width(text: String, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = width
	return label

func _name_of(peer_id: int) -> String:
	for player in NetworkManager.local_players:
		if player.peer_id == peer_id:
			return player.display_name
	return "Игрок"

func _money(value: int) -> String:
	var text := str(absi(value))
	var output := ""
	while text.length() > 3:
		output = " " + text.right(3) + output
		text = text.left(text.length() - 3)
	return ("-" if value < 0 else "") + text + output
