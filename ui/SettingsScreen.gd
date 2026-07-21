extends Control
## Dedicated settings screen; visual/audio options no longer crowd the join card.

const BACKDROP := preload("res://ui/MenuBackdrop.gd")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = LuxuryTheme.create()
	add_child(BACKDROP.new())
	_build_ui()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(590, 640)
	panel.add_theme_stylebox_override("panel", UiPalette.panel(
		Color(0.015, 0.043, 0.031, 0.84),
		Color(UiPalette.GOLD_DARK, 0.65), 14, 1, 26))
	center.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var root := VBoxContainer.new()
	root.custom_minimum_size.x = 525
	root.add_theme_constant_override("separation", 12)
	scroll.add_child(root)

	var title := Label.new()
	title.text = "Настройки"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", UiPalette.GOLD_LIGHT)
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Интерфейс, изображение и звук"
	subtitle.add_theme_color_override("font_color", UiPalette.MUTED)
	root.add_child(subtitle)

	root.add_child(_section("ЭКРАН"))
	var fullscreen := CheckButton.new()
	fullscreen.text = "Полноэкранный режим"
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(func(value: bool):
		GameConfig.fullscreen_enabled = value
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
	)
	root.add_child(fullscreen)
	var vsync := CheckButton.new()
	vsync.text = "Вертикальная синхронизация"
	vsync.button_pressed = GameConfig.vsync_enabled
	vsync.toggled.connect(func(value: bool):
		GameConfig.vsync_enabled = value
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
	)
	root.add_child(vsync)

	var quality_row := HBoxContainer.new()
	var quality_label := Label.new()
	quality_label.text = "Качество эффектов"
	quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_row.add_child(quality_label)
	var quality := OptionButton.new()
	quality.add_item("Низкое")
	quality.add_item("Сбалансированное")
	quality.add_item("Кинематографическое")
	quality.select(GameConfig.effects_quality)
	quality.item_selected.connect(func(index: int): GameConfig.effects_quality = index)
	quality_row.add_child(quality)
	root.add_child(quality_row)

	var motion := CheckButton.new()
	motion.text = "Уменьшить анимации"
	motion.button_pressed = GameConfig.reduced_motion
	motion.toggled.connect(func(value: bool): GameConfig.reduced_motion = value)
	root.add_child(motion)

	root.add_child(_section("ЗВУК"))
	var mute := CheckButton.new()
	mute.text = "Отключить весь звук"
	mute.button_pressed = GameConfig.mute_all
	mute.toggled.connect(func(value: bool):
		GameConfig.mute_all = value
		_apply_audio()
	)
	root.add_child(mute)
	root.add_child(_volume_row("Общая громкость", "master_volume"))
	root.add_child(_volume_row("Музыка", "music_volume"))
	root.add_child(_volume_row("Эффекты", "sfx_volume"))
	root.add_child(_volume_row("Интерфейс", "ui_volume"))

	var hint := Label.new()
	hint.text = "Изменение качества эффектов применяется при следующем входе в игровую сцену."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiPalette.MUTED)
	root.add_child(hint)

	var back := Button.new()
	back.text = "СОХРАНИТЬ И ВЕРНУТЬСЯ"
	back.add_theme_stylebox_override("normal", UiPalette.button(UiPalette.MAHOGANY_LIGHT, UiPalette.GOLD, true))
	back.pressed.connect(_back)
	root.add_child(back)

func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", UiPalette.GOLD)
	return label

func _volume_row(title: String, property: StringName) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 170
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(GameConfig.get(property))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 45
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = "%d%%" % roundi(slider.value * 100.0)
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float):
		GameConfig.set(property, value)
		value_label.text = "%d%%" % roundi(value * 100.0)
		_apply_audio()
	)
	return row

func _apply_audio() -> void:
	var director := get_node_or_null("/root/AudioDirector")
	if director != null:
		director.call("apply_settings")

func _back() -> void:
	GameConfig.save_settings()
	var target := PackRegistry.resolve_scene("main_menu", "res://ui/MainMenu.tscn")
	if NetworkManager.mode != NetworkManager.Mode.NONE \
			and str(NetworkManager.local_snapshot.get("phase", "lobby")) == "lobby":
		target = PackRegistry.resolve_scene("waiting_room", "res://ui/WaitingRoom.tscn")
	get_tree().change_scene_to_file(target)
