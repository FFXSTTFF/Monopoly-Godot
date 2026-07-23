extends Control
## Responsive, animated vanilla lobby in the dark banking-luxury style.

const CUSTOMIZER := preload("res://ui/TokenCustomizer.gd")
const BACKDROP := preload("res://ui/MenuBackdrop.gd")
const WAITING_SCENE := "res://ui/WaitingRoom.tscn"
const SETTINGS_SCENE := "res://ui/SettingsScreen.tscn"
const GAME_SCENE := "res://Game.tscn"

var _host_field: LineEdit
var _port_field: LineEdit
var _name_field: LineEdit
var _ruleset_option: OptionButton
var _status_label: Label
var _ruleset_ids: Array = []
var _content_root: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = LuxuryTheme.create()
	_build_ui()
	EventBus.connection_succeeded.connect(_on_connection_succeeded)
	EventBus.connection_failed.connect(_on_connection_failed)
	EventBus.desync_detected.connect(_on_desync)
	_play_intro()
	_name_field.grab_focus.call_deferred()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()

func _build_ui() -> void:
	add_child(BACKDROP.new())

	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 64)
	safe.add_theme_constant_override("margin_right", 64)
	safe.add_theme_constant_override("margin_top", 58)
	safe.add_theme_constant_override("margin_bottom", 58)
	add_child(safe)

	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 56)
	safe.add_child(layout)
	_content_root = layout

	var brand := _build_brand()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.size_flags_stretch_ratio = 1.5
	layout.add_child(brand)

	var right_center := CenterContainer.new()
	right_center.custom_minimum_size = Vector2(450, 0)
	right_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(right_center)

	var right_column := VBoxContainer.new()
	right_column.custom_minimum_size.x = 430
	right_column.add_theme_constant_override("separation", 10)
	right_center.add_child(right_column)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(430, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(UiPalette.GLASS, 0.74),
		Color(UiPalette.GOLD_DARK, 0.58), 14, 1, 22))
	right_column.add_child(card)

	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 12)
	card.add_child(form)
	_build_form(form)

	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation", 10)
	var customize := Button.new()
	customize.text = "◆  Фигурка"
	customize.tooltip_text = "Выбрать внешний вид фигурки"
	customize.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	customize.pressed.connect(_open_customizer)
	secondary.add_child(customize)
	var settings := Button.new()
	settings.text = "⚙  Настройки"
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.pressed.connect(_open_settings)
	secondary.add_child(settings)
	right_column.add_child(secondary)

	var solo_test := Button.new()
	solo_test.text = "ТЕСТИРОВЩИКАМ: НАЧАТЬ ОДИНОЧНУЮ ИГРУ"
	solo_test.tooltip_text = "Запустить локальную партию без второго игрока"
	solo_test.add_theme_font_size_override("font_size", 12)
	solo_test.pressed.connect(_on_solo_test)
	right_column.add_child(solo_test)

func _build_brand() -> VBoxContainer:
	var brand := VBoxContainer.new()
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", 10)

	var kicker := Label.new()
	kicker.text = "PRIVATE TABLE  •  EST. 2026"
	kicker.add_theme_color_override("font_color", UiPalette.GOLD)
	kicker.add_theme_font_size_override("font_size", 14)
	kicker.add_theme_constant_override("letter_spacing", 4)
	brand.add_child(kicker)

	var title := Label.new()
	title.text = "MONOPOLIS"
	title.add_theme_color_override("font_color", UiPalette.IVORY)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_constant_override("outline_size", 5)
	title.add_theme_color_override("font_outline_color", Color(UiPalette.GOLD_DARK, 0.55))
	brand.add_child(title)

	var gold_line := ColorRect.new()
	gold_line.color = UiPalette.GOLD
	gold_line.custom_minimum_size = Vector2(170, 2)
	gold_line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	brand.add_child(gold_line)

	var subtitle := Label.new()
	subtitle.text = "Деньги любят тишину.\nСделки — правильный момент."
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", UiPalette.MUTED)
	brand.add_child(subtitle)

	var feature := Label.new()
	feature.text = "АВТОРИТАРНЫЙ СЕРВЕР   ·   СКРЫТЫЕ БАЛАНСЫ\nПАКИ И DLC   ·   ПРИВАТНЫЕ ПАРТИИ"
	feature.add_theme_font_size_override("font_size", 13)
	feature.add_theme_color_override("font_color", Color(UiPalette.GOLD_LIGHT, 0.72))
	feature.add_theme_constant_override("line_spacing", 8)
	brand.add_child(feature)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 28
	brand.add_child(spacer)

	var pack_label := Label.new()
	pack_label.text = "%d ПАКОВ ЗАГРУЖЕНО  •  %s" % [
		PackRegistry.loaded_packs.size(),
		PackRegistry.signature.substr(0, 12).to_upper(),
	]
	pack_label.add_theme_font_size_override("font_size", 12)
	pack_label.add_theme_color_override("font_color", Color(UiPalette.MUTED, 0.68))
	brand.add_child(pack_label)
	return brand

func _build_form(form: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Войти за стол"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UiPalette.GOLD_LIGHT)
	form.add_child(title)

	var caption := Label.new()
	caption.text = "Создайте приватную партию или присоединитесь к серверу."
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_color_override("font_color", UiPalette.MUTED)
	form.add_child(caption)
	form.add_child(_separator())

	form.add_child(_field_label("ИМЯ ИГРОКА"))
	_name_field = LineEdit.new()
	_name_field.text = GameConfig.player_name
	_name_field.placeholder_text = "Как к вам обращаться?"
	_name_field.max_length = 24
	form.add_child(_name_field)

	form.add_child(_field_label("РЕЖИМ ИГРЫ"))
	_ruleset_option = OptionButton.new()
	_ruleset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for def in PackRegistry.get_all("rulesets"):
		_ruleset_ids.append(def.get("full_id", ""))
		_ruleset_option.add_item(str(def.get("name", def.get("full_id", "?"))))
	_ruleset_option.item_selected.connect(func(index: int):
		if index >= 0 and index < _ruleset_ids.size():
			GameConfig.selected_ruleset = str(_ruleset_ids[index])
	)
	form.add_child(_ruleset_option)
	_select_ruleset()

	form.add_child(_field_label("СЕРВЕР"))
	var server_row := HBoxContainer.new()
	server_row.add_theme_constant_override("separation", 8)
	_host_field = LineEdit.new()
	_host_field.placeholder_text = "Адрес"
	_host_field.text = GameConfig.last_host
	_host_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_row.add_child(_host_field)
	_port_field = LineEdit.new()
	_port_field.placeholder_text = "Порт"
	_port_field.text = str(GameConfig.last_port)
	_port_field.custom_minimum_size.x = 100
	server_row.add_child(_port_field)
	form.add_child(server_row)

	var host_button := Button.new()
	host_button.text = "ОТКРЫТЬ СВОЙ СТОЛ"
	host_button.add_theme_font_size_override("font_size", 18)
	host_button.add_theme_stylebox_override("normal", UiPalette.button(UiPalette.MAHOGANY_LIGHT, UiPalette.GOLD, true))
	host_button.pressed.connect(_on_host)
	_animate_button(host_button)
	form.add_child(host_button)

	var join_button := Button.new()
	join_button.text = "ПРИСОЕДИНИТЬСЯ"
	join_button.pressed.connect(_on_join)
	_animate_button(join_button)
	form.add_child(join_button)

	_status_label = Label.new()
	_status_label.text = "Готово к подключению."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", UiPalette.SUCCESS)
	_status_label.custom_minimum_size.y = 42
	form.add_child(_status_label)

	var build := Label.new()
	build.text = "VANILLA 0.1  •  API %d  •  ENET SECURE SESSION" % ModLoader.API_VERSION
	build.add_theme_font_size_override("font_size", 10)
	build.add_theme_color_override("font_color", Color(UiPalette.MUTED, 0.45))
	build.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	form.add_child(build)

func _field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", UiPalette.GOLD)
	return label

func _separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 12)
	return separator

func _animate_button(button: Button) -> void:
	button.mouse_entered.connect(func():
		if GameConfig.reduced_motion:
			return
		var tween := button.create_tween()
		tween.tween_property(button, "modulate", Color(1.08, 1.05, 0.92), 0.12)
	)
	button.mouse_exited.connect(func():
		var tween := button.create_tween()
		tween.tween_property(button, "modulate", Color.WHITE, 0.16)
	)

func _play_intro() -> void:
	if GameConfig.reduced_motion:
		return
	_content_root.modulate.a = 0.0
	_content_root.position.y += 24.0
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_content_root, "modulate:a", 1.0, 0.65)
	tween.tween_property(_content_root, "position:y", _content_root.position.y - 24.0, 0.65)

func _select_ruleset() -> void:
	var index := _ruleset_ids.find(GameConfig.selected_ruleset)
	if index < 0 and not _ruleset_ids.is_empty():
		index = 0
		GameConfig.selected_ruleset = str(_ruleset_ids[0])
	if index >= 0:
		_ruleset_option.select(index)

func _open_customizer() -> void:
	var customizer := CUSTOMIZER.new()
	add_child(customizer)

func _open_settings() -> void:
	_persist_fields()
	get_tree().change_scene_to_file(PackRegistry.resolve_scene("settings", SETTINGS_SCENE))

func _persist_fields() -> void:
	GameConfig.player_name = _name_field.text.strip_edges()
	if GameConfig.player_name.is_empty():
		GameConfig.player_name = "Player"
	GameConfig.last_host = _host_field.text.strip_edges()
	GameConfig.last_port = clampi(int(_port_field.text), 1, 65535)
	GameConfig.save_settings()

func _on_host() -> void:
	_persist_fields()
	_set_status("Открываем стол на порту %d…" % GameConfig.last_port, UiPalette.GOLD_LIGHT)
	if NetworkManager.host_game(GameConfig.last_port, GameConfig.selected_ruleset):
		_go_to_waiting()
	else:
		_set_status("Не удалось открыть порт %d." % GameConfig.last_port, UiPalette.DANGER)

func _on_solo_test() -> void:
	_persist_fields()
	_set_status("Запускаем локальный тестовый стол…", UiPalette.GOLD_LIGHT)
	if not NetworkManager.host_solo_test(GameConfig.selected_ruleset):
		_set_status("Не удалось запустить одиночный тест.", UiPalette.DANGER)
		return
	_go_to_game()

func _on_join() -> void:
	_persist_fields()
	_set_status("Подключение к %s:%d…" % [GameConfig.last_host, GameConfig.last_port], UiPalette.GOLD_LIGHT)
	if not NetworkManager.join_game(GameConfig.last_host, GameConfig.last_port):
		_set_status("Проверьте адрес и порт сервера.", UiPalette.DANGER)

func _on_connection_succeeded() -> void:
	_go_to_waiting()

func _on_connection_failed(reason: String) -> void:
	_set_status(reason, UiPalette.DANGER)

func _on_desync(diff: Dictionary) -> void:
	var parts: Array[String] = []
	if not diff.get("missing", []).is_empty():
		parts.append("нет паков: %s" % _ids(diff["missing"]))
	if not diff.get("extra", []).is_empty():
		parts.append("лишние паки: %s" % _ids(diff["extra"]))
	if not diff.get("version_mismatch", []).is_empty():
		parts.append("версии: %s" % _ids(diff["version_mismatch"]))
	_set_status("Несовместимый стол — " + ("; ".join(parts) if not parts.is_empty() else "сигнатуры различаются"), UiPalette.DANGER)

func _ids(items: Array) -> String:
	var output: Array[String] = []
	for entry in items:
		output.append(str(entry.get("id", "?")))
	return ", ".join(output)

func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)

func _go_to_waiting() -> void:
	_transition_to(PackRegistry.resolve_scene("waiting_room", WAITING_SCENE))

func _go_to_game() -> void:
	_transition_to(PackRegistry.resolve_scene("game", GAME_SCENE))

func _transition_to(scene_path: String) -> void:
	if GameConfig.reduced_motion:
		get_tree().change_scene_to_file(scene_path)
		return
	var fade := ColorRect.new()
	fade.color = Color(UiPalette.INK, 0.0)
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fade)
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.32)
	await tween.finished
	get_tree().change_scene_to_file(scene_path)
