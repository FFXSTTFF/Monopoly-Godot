extends Control
## Responsive token atelier with a live, lit 3D preview.

signal closed()
signal saved()

var _token_list: ItemList
var _color_button: ColorPickerButton
var _preview_token: TokenView
var _preview_stage: Node3D
var _token_ids: Array[String] = []
var _panel: PanelContainer
var _accepted := false
var _initial_name := ""
var _initial_token := ""
var _initial_customization: Dictionary = {}

func _ready() -> void:
	_initial_name = GameConfig.player_name
	_initial_token = GameConfig.selected_token
	_initial_customization = GameConfig.token_customization.duplicate(true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = LuxuryTheme.create()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_play_intro()

func _process(delta: float) -> void:
	if _preview_stage != null and not GameConfig.reduced_motion:
		_preview_stage.rotation.y += delta * 0.28

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.012, 0.009, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close()
	)
	add_child(dim)

	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 36)
	safe.add_theme_constant_override("margin_right", 36)
	safe.add_theme_constant_override("margin_top", 30)
	safe.add_theme_constant_override("margin_bottom", 30)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(safe)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(880, 590)
	_panel.add_theme_stylebox_override("panel", UiPalette.panel(Color(0.018, 0.045, 0.033, 0.985), UiPalette.GOLD, 16, 1, 26))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_panel)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 28)
	_panel.add_child(root)

	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 360
	controls.add_theme_constant_override("separation", 12)
	root.add_child(controls)
	_build_controls(controls)

	var preview_card := PanelContainer.new()
	preview_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_card.add_theme_stylebox_override("panel", UiPalette.panel(Color(0.01, 0.025, 0.019, 0.9), UiPalette.GOLD_DARK, 12, 1, 8))
	preview_card.add_child(_build_preview())
	root.add_child(preview_card)
	_select_current_token()

func _build_controls(root: VBoxContainer) -> void:
	var eyebrow := Label.new()
	eyebrow.text = "PRIVATE COLLECTION"
	eyebrow.add_theme_font_size_override("font_size", 11)
	eyebrow.add_theme_color_override("font_color", UiPalette.GOLD)
	root.add_child(eyebrow)

	var title := Label.new()
	title.text = "Ваша фигурка"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", UiPalette.GOLD_LIGHT)
	root.add_child(title)

	var description := Label.new()
	description.text = "Выберите символ, который будет представлять вас за столом."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", UiPalette.MUTED)
	root.add_child(description)

	var name_label := _caption("ИМЯ ИГРОКА")
	root.add_child(name_label)
	var name_field := LineEdit.new()
	name_field.placeholder_text = "Имя"
	name_field.text = GameConfig.player_name
	name_field.max_length = 24
	name_field.text_changed.connect(func(text: String): GameConfig.player_name = text)
	root.add_child(name_field)

	root.add_child(_caption("КОЛЛЕКЦИЯ"))
	_token_list = ItemList.new()
	_token_list.custom_minimum_size = Vector2(0, 180)
	_token_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_token_list.allow_reselect = true
	for definition in PackRegistry.get_all("tokens"):
		_token_ids.append(str(definition.get("full_id", "")))
		_token_list.add_item("◆  " + str(definition.get("name", definition.get("full_id", "?"))))
	_token_list.item_selected.connect(_on_token_selected)
	root.add_child(_token_list)

	var color_row := HBoxContainer.new()
	color_row.add_child(_caption("ЦВЕТ МЕТАЛЛА"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_row.add_child(spacer)
	_color_button = ColorPickerButton.new()
	_color_button.custom_minimum_size = Vector2(84, 34)
	_color_button.color = ColorUtil.to_color(GameConfig.token_customization.get("color", UiPalette.GOLD))
	_color_button.color_changed.connect(_on_color_changed)
	color_row.add_child(_color_button)
	root.add_child(color_row)

	var material_row := HBoxContainer.new()
	material_row.add_child(_caption("ОТДЕЛКА"))
	var material_spacer := Control.new()
	material_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	material_row.add_child(material_spacer)
	var material_option := OptionButton.new()
	material_option.add_item("Полированный металл")
	material_option.add_item("Матовый металл")
	material_option.add_item("Эмаль")
	var finishes := ["polished", "brushed", "enamel"]
	var current_finish := str(GameConfig.token_customization.get("material", "polished"))
	material_option.select(maxi(0, finishes.find(current_finish)))
	material_option.item_selected.connect(func(index: int):
		GameConfig.token_customization["material"] = finishes[index]
		_update_preview()
	)
	material_row.add_child(material_option)
	root.add_child(material_row)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var cancel := Button.new()
	cancel.text = "Отмена"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_close)
	buttons.add_child(cancel)
	var accept := Button.new()
	accept.text = "СОХРАНИТЬ"
	accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept.add_theme_stylebox_override("normal", UiPalette.button(UiPalette.MAHOGANY_LIGHT, UiPalette.GOLD, true))
	accept.pressed.connect(_save_and_close)
	buttons.add_child(accept)
	root.add_child(buttons)

func _build_preview() -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(420, 530)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var viewport := SubViewport.new()
	viewport.size = Vector2i(840, 1060)
	viewport.size_2d_override = Vector2i(420, 530)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.008, 0.02, 0.014)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.22, 0.28, 0.24)
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.25, 3.15)
	camera.rotation_degrees = Vector3(-10, 0, 0)
	camera.fov = 34
	world.add_child(camera)

	var key := SpotLight3D.new()
	key.position = Vector3(-1.6, 2.8, 2.2)
	key.rotation_degrees = Vector3(-45, -25, 0)
	key.light_color = Color("#ffe0a0")
	key.light_energy = 6.0
	key.spot_range = 8.0
	key.shadow_enabled = true
	world.add_child(key)

	var rim := OmniLight3D.new()
	rim.position = Vector3(1.5, 1.2, -1.0)
	rim.light_color = Color("#7ba9d8")
	rim.light_energy = 3.0
	rim.omni_range = 5.0
	world.add_child(rim)

	var pedestal := MeshInstance3D.new()
	var pedestal_mesh := CylinderMesh.new()
	pedestal_mesh.top_radius = 0.72
	pedestal_mesh.bottom_radius = 0.82
	pedestal_mesh.height = 0.22
	pedestal.mesh = pedestal_mesh
	pedestal.position.y = -0.13
	var pedestal_material := StandardMaterial3D.new()
	pedestal_material.albedo_color = UiPalette.MAHOGANY_LIGHT
	pedestal_material.metallic = 0.35
	pedestal_material.roughness = 0.28
	pedestal.material_override = pedestal_material
	world.add_child(pedestal)

	_preview_stage = Node3D.new()
	world.add_child(_preview_stage)
	_preview_token = TokenView.new()
	_preview_stage.add_child(_preview_token)
	return container

func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", UiPalette.GOLD)
	return label

func _current_token_def() -> Dictionary:
	var definition := PackRegistry.get_def("tokens", GameConfig.selected_token)
	if definition.is_empty():
		var all := PackRegistry.get_all("tokens")
		definition = all[0] if not all.is_empty() else {}
	return definition

func _select_current_token() -> void:
	var index := _token_ids.find(GameConfig.selected_token)
	if index < 0 and not _token_ids.is_empty():
		index = 0
		GameConfig.selected_token = _token_ids[0]
	if index >= 0:
		_token_list.select(index)
	_update_preview()

func _on_token_selected(index: int) -> void:
	if index >= 0 and index < _token_ids.size():
		GameConfig.selected_token = _token_ids[index]
		_update_preview()

func _on_color_changed(color: Color) -> void:
	GameConfig.token_customization["color"] = color
	_update_preview()

func _update_preview() -> void:
	if _preview_token == null:
		return
	_preview_token.setup(_current_token_def(), GameConfig.token_customization)

func _play_intro() -> void:
	if GameConfig.reduced_motion:
		return
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.96, 0.96)
	_panel.pivot_offset = _panel.custom_minimum_size * 0.5
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.28)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.34)

func _save_and_close() -> void:
	_accepted = true
	GameConfig.save_settings()
	saved.emit()
	_close()

func _close() -> void:
	if not _accepted:
		GameConfig.player_name = _initial_name
		GameConfig.selected_token = _initial_token
		GameConfig.token_customization = _initial_customization
	closed.emit()
	if GameConfig.reduced_motion:
		queue_free()
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.16)
	tween.tween_property(_panel, "scale", Vector2(0.97, 0.97), 0.16)
	await tween.finished
	queue_free()
