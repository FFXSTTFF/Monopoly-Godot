extends Control
## Dedicated pre-game room. No 3D board is loaded until the host starts.

const BACKDROP := preload("res://ui/MenuBackdrop.gd")
const CUSTOMIZER := preload("res://ui/TokenCustomizer.gd")

var _players_box: VBoxContainer
var _ready_button: Button
var _start_button: Button
var _status: Label
var _transitioning := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = LuxuryTheme.create()
	add_child(BACKDROP.new())
	_build_ui()
	EventBus.game_state_changed.connect(_on_snapshot)
	EventBus.connection_failed.connect(_on_connection_failed)
	_refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_leave()

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 610)
	panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(UiPalette.GLASS, 0.82),
		Color(UiPalette.GOLD_DARK, 0.62), 15, 1, 26))
	center.add_child(panel)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 28)
	panel.add_child(layout)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	layout.add_child(left)
	var kicker := Label.new()
	kicker.text = "PRIVATE WAITING ROOM"
	kicker.add_theme_font_size_override("font_size", 11)
	kicker.add_theme_color_override("font_color", UiPalette.GOLD)
	left.add_child(kicker)
	var title := Label.new()
	title.text = "Комната ожидания"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", UiPalette.GOLD_LIGHT)
	left.add_child(title)
	_status = Label.new()
	_status.text = "Синхронизация со столом…"
	_status.add_theme_color_override("font_color", UiPalette.MUTED)
	left.add_child(_status)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 7)
	_players_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_players_box)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 310
	right.add_theme_constant_override("separation", 12)
	layout.add_child(right)
	right.add_child(_info_label("РЕЖИМ", _ruleset_name()))
	right.add_child(_info_label("СЕРВЕР", "%s:%d" % [GameConfig.last_host, GameConfig.last_port]))
	right.add_child(_info_label("СИГНАТУРА ПАКОВ", PackRegistry.signature.substr(0, 16).to_upper()))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)

	_ready_button = Button.new()
	_ready_button.text = "Я ГОТОВ"
	_ready_button.toggle_mode = true
	_ready_button.pressed.connect(_toggle_ready)
	right.add_child(_ready_button)
	_start_button = Button.new()
	_start_button.text = "НАЧАТЬ ПАРТИЮ"
	_start_button.add_theme_stylebox_override("normal", UiPalette.button(UiPalette.MAHOGANY_LIGHT, UiPalette.GOLD, true))
	_start_button.pressed.connect(func(): NetworkManager.request_start())
	right.add_child(_start_button)

	var secondary := HBoxContainer.new()
	var token := Button.new()
	token.text = "Фигурка"
	token.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	token.pressed.connect(_open_customizer)
	secondary.add_child(token)
	var settings := Button.new()
	settings.text = "Настройки"
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.pressed.connect(func(): get_tree().change_scene_to_file(
		PackRegistry.resolve_scene("settings", "res://ui/SettingsScreen.tscn")))
	secondary.add_child(settings)
	right.add_child(secondary)
	var leave := Button.new()
	leave.text = "Покинуть комнату"
	leave.pressed.connect(_leave)
	right.add_child(leave)

func _info_label(caption: String, value: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", UiPalette.GOLD)
	box.add_child(cap)
	var content := Label.new()
	content.text = value
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_theme_color_override("font_color", UiPalette.IVORY)
	box.add_child(content)
	return box

func _ruleset_name() -> String:
	var definition := PackRegistry.get_def("rulesets", GameConfig.selected_ruleset)
	return str(definition.get("name", GameConfig.selected_ruleset))

func _on_snapshot(snapshot: Dictionary) -> void:
	if str(snapshot.get("phase", "lobby")) == "playing":
		_enter_game()
		return
	_refresh()

func _refresh() -> void:
	for child in _players_box.get_children():
		child.queue_free()
	var local_peer := NetworkManager.get_local_peer_id()
	var owner := int(NetworkManager.local_snapshot.get("table_owner", 1))
	for player in NetworkManager.local_players:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiPalette.panel(
			Color(UiPalette.GLASS, 0.58),
			Color(UiPalette.GOLD_DARK, 0.35), 8, 1, 9))
		var horizontal := HBoxContainer.new()
		row.add_child(horizontal)
		var marker := Label.new()
		marker.text = "◆" if player.peer_id == owner else "◇"
		marker.add_theme_color_override("font_color", UiPalette.GOLD)
		horizontal.add_child(marker)
		var name := Label.new()
		var token_def := PackRegistry.get_def("tokens", player.token_id)
		name.text = "%s  ·  %s%s" % [
			player.display_name,
			str(token_def.get("name", player.token_id)),
			"  [ВЫ]" if player.peer_id == local_peer else ""]
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		horizontal.add_child(name)
		var state := Label.new()
		state.text = "ГОТОВ" if player.ready else "ОЖИДАЕТ"
		state.add_theme_color_override("font_color", UiPalette.SUCCESS if player.ready else UiPalette.MUTED)
		horizontal.add_child(state)
		_players_box.add_child(row)
	var local_player := _local_player()
	_ready_button.button_pressed = local_player != null and local_player.ready
	_ready_button.text = "ГОТОВ" if _ready_button.button_pressed else "Я ГОТОВ"
	var is_owner := local_peer == owner
	_start_button.visible = is_owner
	_start_button.disabled = not bool(NetworkManager.local_snapshot.get("can_start", false))
	_status.text = "%d / %d игроков • ожидаем готовность" % [
		NetworkManager.local_players.size(),
		int(NetworkManager.local_snapshot.get("min_players", 2))]

func _toggle_ready() -> void:
	NetworkManager.request_lobby_ready(_ready_button.button_pressed)

func _open_customizer() -> void:
	var customizer := CUSTOMIZER.new()
	customizer.saved.connect(NetworkManager.request_profile_update)
	add_child(customizer)

func _local_player() -> PlayerState:
	var peer := NetworkManager.get_local_peer_id()
	for player in NetworkManager.local_players:
		if player.peer_id == peer:
			return player
	return null

func _enter_game() -> void:
	if _transitioning:
		return
	_transitioning = true
	get_tree().change_scene_to_file(PackRegistry.resolve_scene("game", "res://Game.tscn"))

func _on_connection_failed(reason: String) -> void:
	_status.text = reason
	_status.add_theme_color_override("font_color", UiPalette.DANGER)

func _leave() -> void:
	NetworkManager.disconnect_session()
	get_tree().change_scene_to_file(PackRegistry.resolve_scene(
		"main_menu", "res://ui/MainMenu.tscn"))
