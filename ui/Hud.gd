extends Control
## Gameplay-only HUD with contextual actions for the authoritative turn phase.

const ASSET_DIALOG := preload("res://ui/AssetDialog.gd")
const TRADE_DIALOG := preload("res://ui/TradeDialog.gd")

var _balance_label: Label
var _turn_label: Label
var _phase_label: Label
var _die: Label
var _players_box: VBoxContainer
var _context_panel: PanelContainer
var _context_title: Label
var _context_body: Label
var _context_actions: HBoxContainer
var _toast: Label
var _trade_button: Button
var _last_balance := -1
var _shown_trade_ids: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = LuxuryTheme.create()
	_build_ui()
	EventBus.local_balance_changed.connect(_on_balance)
	EventBus.game_state_changed.connect(func(_snapshot: Dictionary): _refresh())
	EventBus.private_state_changed.connect(func(_state: Dictionary):
		_refresh()
		_check_incoming_trades())
	EventBus.turn_changed.connect(func(_peer: int): _refresh())
	EventBus.dice_rolled.connect(_on_dice)
	EventBus.game_action.connect(_on_game_action)
	_on_balance(NetworkManager.local_balance)
	_refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_leave()

func _build_ui() -> void:
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, 18)
	add_child(safe)
	var screen := VBoxContainer.new()
	safe.add_child(screen)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	screen.add_child(top)
	_build_balance(top)
	var stretch_left := Control.new()
	stretch_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(stretch_left)
	_build_turn(top)
	var stretch_right := Control.new()
	stretch_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(stretch_right)
	_build_players(top)

	var middle := CenterContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.add_child(middle)
	_toast = Label.new()
	_toast.visible = false
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_stylebox_override("normal", UiPalette.panel(
		Color(UiPalette.GLASS, 0.95), UiPalette.GOLD_DARK, 8, 1, 12))
	middle.add_child(_toast)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 10)
	bottom.mouse_filter = Control.MOUSE_FILTER_PASS
	screen.add_child(bottom)
	var leave := Button.new()
	leave.text = "Выйти"
	leave.pressed.connect(_leave)
	bottom.add_child(leave)
	var assets := Button.new()
	assets.text = "Активы"
	assets.pressed.connect(func(): add_child(ASSET_DIALOG.new()))
	bottom.add_child(assets)
	_context_panel = PanelContainer.new()
	_context_panel.custom_minimum_size = Vector2(520, 0)
	_context_panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(UiPalette.GLASS, 0.96), UiPalette.GOLD, 10, 1, 12))
	bottom.add_child(_context_panel)
	var context := VBoxContainer.new()
	context.add_theme_constant_override("separation", 5)
	_context_panel.add_child(context)
	_context_title = Label.new()
	_context_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_title.add_theme_color_override("font_color", UiPalette.GOLD_LIGHT)
	context.add_child(_context_title)
	_context_body = Label.new()
	_context_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_body.add_theme_font_size_override("font_size", 12)
	_context_body.add_theme_color_override("font_color", UiPalette.MUTED)
	context.add_child(_context_body)
	_context_actions = HBoxContainer.new()
	_context_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_context_actions.add_theme_constant_override("separation", 7)
	context.add_child(_context_actions)
	_trade_button = Button.new()
	_trade_button.text = "Сделка"
	_trade_button.pressed.connect(func(): add_child(TRADE_DIALOG.new()))
	bottom.add_child(_trade_button)

func _build_balance(parent: HBoxContainer) -> void:
	var panel := _card(Vector2(255, 0))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(_caption("PRIVATE ACCOUNT"))
	var name := Label.new()
	name.text = GameConfig.player_name
	name.add_theme_color_override("font_color", UiPalette.MUTED)
	box.add_child(name)
	_balance_label = Label.new()
	_balance_label.add_theme_font_size_override("font_size", 26)
	_balance_label.add_theme_color_override("font_color", UiPalette.GOLD_LIGHT)
	box.add_child(_balance_label)

func _build_turn(parent: HBoxContainer) -> void:
	var panel := _card(Vector2(310, 0))
	panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(UiPalette.GLASS, 0.94), UiPalette.GOLD, 11, 1, 12))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	_phase_label = _caption("ХОД")
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_phase_label)
	_turn_label = Label.new()
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.add_theme_font_size_override("font_size", 20)
	box.add_child(_turn_label)
	_die = Label.new()
	_die.text = "—"
	_die.custom_minimum_size = Vector2(42, 40)
	_die.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_die.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_die.add_theme_font_size_override("font_size", 22)
	_die.add_theme_color_override("font_color", Color("#24140d"))
	box.add_child(_die)

func _build_players(parent: HBoxContainer) -> void:
	var panel := _card(Vector2(270, 0))
	parent.add_child(panel)
	_players_box = VBoxContainer.new()
	panel.add_child(_players_box)

func _refresh() -> void:
	if _context_actions == null:
		return
	var snapshot := NetworkManager.local_snapshot
	var me := NetworkManager.get_local_peer_id()
	var current := int(snapshot.get("current_peer", 0))
	var my_turn := current == me
	_phase_label.text = str(snapshot.get("turn_phase", "playing")).replace("_", " ").to_upper()
	_turn_label.text = "Ваш ход" if my_turn else _name_of(current)
	_rebuild_players()
	_clear_actions()
	if str(snapshot.get("phase", "")) == "ended":
		_context_title.text = "Партия завершена"
		_context_body.text = "Победитель: %s" % _name_of(int(snapshot.get("winner_peer", 0)))
		return
	var turn_phase := str(snapshot.get("turn_phase", ""))
	_trade_button.disabled = turn_phase != "awaiting_roll"
	var pending: Dictionary = snapshot.get("pending_action", {})
	var auction: Dictionary = snapshot.get("auction", {})
	if turn_phase == "awaiting_roll" and my_turn:
		_context_title.text = "Бросок"
		_context_body.text = "Один кубик • движение на 1–6 клеток"
		_add_action("БРОСИТЬ КУБИК", NetworkManager.request_roll, true)
	elif turn_phase == "awaiting_purchase" and int(pending.get("peer_id", 0)) == me:
		var index := int(pending.get("cell_index", -1))
		var cell := NetworkManager.local_board.get_cell(index)
		_context_title.text = str(cell.get("name", "Собственность"))
		_context_body.text = "Цена: %s $" % _money(int(cell.get("price", 0)))
		_add_action("КУПИТЬ", NetworkManager.request_buy, true)
		_add_action("НЕ ПОКУПАТЬ", NetworkManager.request_decline_purchase)
	elif turn_phase == "awaiting_auction" and bool(auction.get("active", false)):
		_build_auction_actions(auction)
	elif turn_phase == "awaiting_jail" and my_turn:
		_context_title.text = "Тюрьма"
		_context_body.text = "Штраф: %s $ • либо пропустить ход" % _money(100000)
		_add_action("ЗАПЛАТИТЬ", func(): NetworkManager.request_jail_action("pay"), true)
		_add_action("ИСПОЛЬЗОВАТЬ КАРТУ", func(): NetworkManager.request_jail_action("card"))
		_add_action("ПРОПУСТИТЬ", func(): NetworkManager.request_jail_action("wait"))
	elif turn_phase == "managing_assets" and int(pending.get("peer_id", 0)) == me:
		var debt: Dictionary = NetworkManager.local_private_state.get("debt", {})
		_context_title.text = "Недостаточно средств"
		_context_body.text = "Нужно оплатить: %s $. Продайте постройки или заложите активы." % _money(int(debt.get("amount", 0)))
		_add_action("УПРАВЛЯТЬ АКТИВАМИ", func(): add_child(ASSET_DIALOG.new()), true)
		_add_action("БАНКРОТСТВО", NetworkManager.request_bankruptcy)
	else:
		_context_title.text = "Стол ждёт решения"
		_context_body.text = _name_of(current)

func _build_auction_actions(auction: Dictionary) -> void:
	_context_title.text = "Закрытый аукцион"
	var index := int(auction.get("property_index", -1))
	var cell := NetworkManager.local_board.get_cell(index)
	_context_body.text = "%s • ответили %d/%d" % [
		str(cell.get("name", "?")),
		int(auction.get("responded", 0)),
		int(auction.get("total", 0))]
	if bool(NetworkManager.local_private_state.get("auction_responded", false)):
		var waiting := Label.new()
		waiting.text = "Ставка принята. Ожидание остальных."
		waiting.add_theme_color_override("font_color", UiPalette.MUTED)
		_context_actions.add_child(waiting)
		return
	var bid := SpinBox.new()
	bid.min_value = 10000
	bid.max_value = NetworkManager.local_balance
	bid.step = 10000
	bid.value = mini(100000, NetworkManager.local_balance)
	bid.suffix = " $"
	bid.custom_minimum_size.x = 160
	_context_actions.add_child(bid)
	_add_action("СТАВКА", func(): NetworkManager.request_auction_bid(int(bid.value)), true)
	_add_action("ПАС", func(): NetworkManager.request_auction_bid(0))

func _rebuild_players() -> void:
	for child in _players_box.get_children():
		child.queue_free()
	_players_box.add_child(_caption("PLAYERS"))
	var me := NetworkManager.get_local_peer_id()
	var current := int(NetworkManager.local_snapshot.get("current_peer", 0))
	for player in NetworkManager.local_players:
		var row := HBoxContainer.new()
		var marker := Label.new()
		marker.text = "◆" if player.peer_id == current else "◇"
		marker.add_theme_color_override("font_color", UiPalette.GOLD)
		row.add_child(marker)
		var name := Label.new()
		name.text = player.display_name + (" [БАНКРОТ]" if player.bankrupt else "")
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var cash := Label.new()
		cash.text = _money(NetworkManager.local_balance) + " $" if player.peer_id == me else "СКРЫТО"
		cash.add_theme_font_size_override("font_size", 11)
		cash.add_theme_color_override("font_color", UiPalette.GOLD_LIGHT if player.peer_id == me else UiPalette.MUTED)
		row.add_child(cash)
		_players_box.add_child(row)

func _on_balance(amount: int) -> void:
	_balance_label.text = "%s $" % _money(amount)
	if _last_balance >= 0 and amount != _last_balance:
		_show_toast(("+" if amount > _last_balance else "") + _money(amount - _last_balance) + " $")
	_last_balance = amount

func _on_dice(_peer: int, values: Array) -> void:
	_die.text = str(values[0]) if not values.is_empty() else "—"
	if not GameConfig.reduced_motion:
		_die.scale = Vector2(0.7, 0.7)
		create_tween().tween_property(_die, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)

func _on_game_action(event_name: String, data: Dictionary) -> void:
	match event_name:
		"purchase": _show_toast("Собственность приобретена")
		"card":
			var card: Dictionary = data.get("card", {})
			_show_toast("%s — %s" % [str(card.get("title", "Карточка")), str(card.get("text", ""))])
		"jail": _show_toast("Игрок отправлен в тюрьму")
		"rent": _show_toast("Аренда перечислена владельцу")
		"auction_started": _show_toast("Начался закрытый аукцион")
		"auction_resolved": _show_toast("Аукцион завершён")
		"build": _show_toast("Постройка завершена")
		"sell_property": _show_toast("Собственность продана банку")
		"mortgage": _show_toast("Актив заложен")
		"bankruptcy": _show_toast("%s объявляет банкротство" % _name_of(int(data.get("peer_id", 0))))

func _check_incoming_trades() -> void:
	var me := NetworkManager.get_local_peer_id()
	for trade_value in NetworkManager.local_private_state.get("trades", []):
		var trade: Dictionary = trade_value
		var id := int(trade.get("trade_id", 0))
		if int(trade.get("to_peer", 0)) != me or _shown_trade_ids.has(id):
			continue
		_shown_trade_ids[id] = true
		var dialog := TRADE_DIALOG.new()
		dialog.incoming_trade = trade
		add_child(dialog)

func _add_action(text: String, callable: Callable, primary: bool = false) -> void:
	var button := Button.new()
	button.text = text
	if primary:
		button.add_theme_stylebox_override("normal", UiPalette.button(UiPalette.MAHOGANY_LIGHT, UiPalette.GOLD, true))
	button.pressed.connect(callable)
	_context_actions.add_child(button)

func _clear_actions() -> void:
	for child in _context_actions.get_children():
		child.queue_free()

func _show_toast(text: String) -> void:
	_toast.text = "  " + text + "  "
	_toast.visible = true
	_toast.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.8)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.25)
	tween.finished.connect(func(): _toast.visible = false)

func _card(minimum: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(UiPalette.GLASS, 0.92), Color(UiPalette.GOLD_DARK, 0.75), 10, 1, 11))
	return panel

func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UiPalette.GOLD)
	return label

func _leave() -> void:
	NetworkManager.disconnect_session()
	get_tree().change_scene_to_file(PackRegistry.resolve_scene(
		"main_menu", "res://ui/MainMenu.tscn"))

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
