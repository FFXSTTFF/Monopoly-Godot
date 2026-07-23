class_name AssetDialog
extends Control
## Asset management used for building, mortgage and debt recovery.

var _list: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = LuxuryTheme.create()
	_build()
	EventBus.game_state_changed.connect(_on_state)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 620)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	var title := Label.new()
	title.text = "Управление активами"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiPalette.GOLD_LIGHT)
	root.add_child(title)
	var balance := Label.new()
	balance.text = "Доступно: %s $" % _money(NetworkManager.local_balance)
	balance.add_theme_color_override("font_color", UiPalette.GOLD)
	root.add_child(balance)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size.x = 720
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var close := Button.new()
	close.text = "ЗАКРЫТЬ"
	close.pressed.connect(queue_free)
	root.add_child(close)
	_rebuild()

func _on_state(_snapshot: Dictionary) -> void:
	if is_instance_valid(_list):
		_rebuild()

func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	var peer := NetworkManager.get_local_peer_id()
	var found := false
	for state_value in NetworkManager.local_snapshot.get("properties", []):
		var state: Dictionary = state_value
		if int(state.get("owner_peer", 0)) != peer:
			continue
		found = true
		_add_property_row(state)
	if not found:
		var empty := Label.new()
		empty.text = "У вас пока нет собственности."
		empty.add_theme_color_override("font_color", UiPalette.MUTED)
		_list.add_child(empty)

func _add_property_row(state: Dictionary) -> void:
	var index := int(state.get("index", -1))
	var cell := NetworkManager.local_board.get_cell(index)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(UiPalette.GLASS, 0.7), Color(UiPalette.GOLD_DARK, 0.4), 7, 1, 8))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	row.add_child(content)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := Label.new()
	name.text = str(cell.get("name", "Собственность"))
	name.add_theme_color_override("font_color", ColorUtil.to_color(cell.get("color", UiPalette.GOLD)))
	info.add_child(name)
	var level := int(state.get("improvements", 0))
	var details := Label.new()
	details.text = ("ОТЕЛЬ" if level == 5 else "%d домов" % level) \
		+ (" • ЗАЛОЖЕНО" if bool(state.get("mortgaged", false)) else "")
	details.add_theme_font_size_override("font_size", 11)
	details.add_theme_color_override("font_color", UiPalette.MUTED)
	info.add_child(details)
	var rent_table: Array = cell.get("rent_table", [])
	var base_rent := int(rent_table[0]) if not rent_table.is_empty() else 0
	var prices := Label.new()
	prices.text = "Покупка: %s $  •  Аренда: %s $  •  Залог: %s $" % [
		_money(int(cell.get("price", 0))),
		_money(base_rent),
		_money(GameRules.mortgage_value(cell))]
	if str(cell.get("type", "")) == "property":
		prices.text += "  •  Дом: %s $" % _money(int(cell.get("house_cost", 0)))
	prices.add_theme_font_size_override("font_size", 11)
	prices.add_theme_color_override("font_color", UiPalette.GOLD_LIGHT)
	info.add_child(prices)
	content.add_child(info)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 5)
	content.add_child(actions)
	if str(cell.get("type", "")) == "property" and not bool(state.get("mortgaged", false)):
		var build := Button.new()
		build.text = "Дом +  −%s $" % _money(int(cell.get("house_cost", 0)))
		build.pressed.connect(func(): NetworkManager.request_build(index))
		actions.add_child(build)
		if level > 0:
			var sell := Button.new()
			sell.text = "Продать дом  +%s $" % _money(int(cell.get("house_cost", 0)) / 2)
			sell.pressed.connect(func(): NetworkManager.request_sell_building(index))
			actions.add_child(sell)
	var mortgage := Button.new()
	var mortgage_value := GameRules.mortgage_value(cell)
	mortgage.text = (
		"Выкупить  −%s $" % _money(roundi(mortgage_value * _unmortgage_multiplier()))
		if bool(state.get("mortgaged", false))
		else "Заложить  +%s $" % _money(mortgage_value))
	mortgage.pressed.connect(func():
		if bool(state.get("mortgaged", false)):
			NetworkManager.request_unmortgage(index)
		else:
			NetworkManager.request_mortgage(index)
	)
	actions.add_child(mortgage)
	if level == 0 and not bool(state.get("mortgaged", false)) \
			and not _group_has_buildings(str(cell.get("group", ""))):
		var sell_property := Button.new()
		var sale_value := GameRules.sale_value(cell, _sale_multiplier())
		sell_property.text = "Продать поле  +%s $" % _money(sale_value)
		sell_property.add_theme_color_override("font_color", UiPalette.DANGER)
		sell_property.pressed.connect(func(): NetworkManager.request_sell_property(index))
		actions.add_child(sell_property)
	_list.add_child(row)

func _sale_multiplier() -> float:
	var ruleset_id := str(NetworkManager.local_snapshot.get("ruleset_id", ""))
	var ruleset := PackRegistry.get_def("rulesets", ruleset_id)
	return float(ruleset.get("property_sale_multiplier", 0.5))

func _unmortgage_multiplier() -> float:
	var ruleset_id := str(NetworkManager.local_snapshot.get("ruleset_id", ""))
	var ruleset := PackRegistry.get_def("rulesets", ruleset_id)
	return float(ruleset.get("unmortgage_multiplier", 1.1))

func _group_has_buildings(group_id: String) -> bool:
	if group_id == "":
		return false
	for state_value in NetworkManager.local_snapshot.get("properties", []):
		var state: Dictionary = state_value
		var index := int(state.get("index", -1))
		if str(NetworkManager.local_board.get_cell(index).get("group", "")) == group_id \
				and int(state.get("improvements", 0)) > 0:
			return true
	return false

func _money(value: int) -> String:
	var text := str(absi(value))
	var output := ""
	while text.length() > 3:
		output = " " + text.right(3) + output
		text = text.left(text.length() - 3)
	return ("-" if value < 0 else "") + text + output
