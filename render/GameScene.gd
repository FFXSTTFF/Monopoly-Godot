extends Node3D
## Cinematic 2.5D table and responsive framing for the vanilla game.

const BOARD_RENDERER := preload("res://render/BoardRenderer.gd")
const HUD_SCRIPT := preload("res://ui/Hud.gd")
const FELT_SHADER := preload("res://render/shaders/felt.gdshader")
const WOOD_SHADER := preload("res://render/shaders/wood.gdshader")
const GOLD_SHADER := preload("res://render/shaders/gold.gdshader")
const VIGNETTE_SHADER := preload("res://render/shaders/vignette.gdshader")

var _camera: Camera3D
var _table_size := 15.0 * BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN

func _ready() -> void:
	_setup_environment()
	_setup_table()
	_setup_lights()
	_setup_camera()
	_setup_particles()
	var board := BOARD_RENDERER.new()
	board.name = "Board"
	add_child(board)
	_setup_vignette()
	_setup_hud()
	EventBus.game_state_changed.connect(_on_game_state_changed)
	get_viewport().size_changed.connect(_fit_camera)
	call_deferred("_fit_camera")

func _on_game_state_changed(_snapshot: Dictionary) -> void:
	if NetworkManager.local_board != null:
		_table_size = maxf(
			15.0 * BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN,
			float(NetworkManager.local_board.size) * BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN)
	_fit_camera()

func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#050806")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#385346")
	environment.ambient_light_energy = 0.44
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.15
	environment.glow_enabled = GameConfig.effects_quality > 0
	environment.glow_intensity = 0.26
	environment.glow_bloom = 0.10
	environment.glow_hdr_threshold = 1.05
	environment.ssao_enabled = GameConfig.effects_quality > 0
	environment.ssao_radius = 1.25
	environment.ssao_intensity = 0.72
	environment.fog_enabled = GameConfig.effects_quality > 1
	environment.fog_light_color = Color("#17271f")
	environment.fog_density = 0.006
	environment.fog_height = 1.0
	environment.fog_height_density = 0.18
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

func _setup_table() -> void:
	var ruleset := PackRegistry.get_def("rulesets", str(NetworkManager.local_snapshot.get("ruleset_id", "")))
	var custom := AssetLoader.instantiate_from_def(ruleset, "table_model")
	if custom != null:
		custom.scale = Vector3.ONE * _table_size
		add_child(custom)
		return

	var table := Node3D.new()
	table.name = "LuxuryTable"
	add_child(table)

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(_table_size + 2.2, 0.72, _table_size + 2.2)
	base.mesh = base_mesh
	base.position.y = -0.52
	base.material_override = _shader_material(WOOD_SHADER)
	table.add_child(base)

	var felt := MeshInstance3D.new()
	var felt_mesh := PlaneMesh.new()
	felt_mesh.size = Vector2(_table_size, _table_size)
	felt.mesh = felt_mesh
	felt.position.y = -0.145
	felt.material_override = _shader_material(FELT_SHADER)
	table.add_child(felt)

	var rail_half := (_table_size + 1.1) * 0.5
	var rail_length := _table_size + 2.2
	_add_rail(table, Vector3(0, -0.05, -rail_half), Vector3(rail_length, 0.42, 0.62))
	_add_rail(table, Vector3(0, -0.05, rail_half), Vector3(rail_length, 0.42, 0.62))
	_add_rail(table, Vector3(-rail_half, -0.05, 0), Vector3(0.62, 0.42, rail_length))
	_add_rail(table, Vector3(rail_half, -0.05, 0), Vector3(0.62, 0.42, rail_length))

	# Thin gold inlay catches the warm key light.
	var gold_material := _shader_material(GOLD_SHADER)
	var inset := _table_size * 0.5 + 0.18
	_add_trim(table, Vector3(0, 0.18, -inset), Vector3(_table_size + 0.45, 0.055, 0.055), gold_material)
	_add_trim(table, Vector3(0, 0.18, inset), Vector3(_table_size + 0.45, 0.055, 0.055), gold_material)
	_add_trim(table, Vector3(-inset, 0.18, 0), Vector3(0.055, 0.055, _table_size + 0.45), gold_material)
	_add_trim(table, Vector3(inset, 0.18, 0), Vector3(0.055, 0.055, _table_size + 0.45), gold_material)

func _add_rail(parent: Node3D, position: Vector3, size: Vector3) -> void:
	var rail := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	rail.mesh = mesh
	rail.position = position
	rail.material_override = _shader_material(WOOD_SHADER)
	parent.add_child(rail)

func _add_trim(parent: Node3D, position: Vector3, size: Vector3, material: Material) -> void:
	var trim := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	trim.mesh = mesh
	trim.position = position
	trim.material_override = material
	parent.add_child(trim)

func _setup_lights() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58, -38, 0)
	key.light_energy = 1.55
	key.light_color = Color("#ffdba0")
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 45.0
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-34, 142, 0)
	fill.light_energy = 0.42
	fill.light_color = Color("#7198b7")
	add_child(fill)

	var warm_pool := SpotLight3D.new()
	warm_pool.position = Vector3(-6.5, 10.5, 4.5)
	warm_pool.rotation_degrees = Vector3(-62, -28, 0)
	warm_pool.light_color = Color("#f0b85c")
	warm_pool.light_energy = 4.2
	warm_pool.spot_range = 24.0
	warm_pool.spot_angle = 48.0
	warm_pool.shadow_enabled = GameConfig.effects_quality > 0
	add_child(warm_pool)

func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.position = Vector3(0, 18.5, 10.0)
	_camera.rotation_degrees = Vector3(-62.0, 0, 0)
	_camera.current = true
	add_child(_camera)

func _fit_camera() -> void:
	if _camera == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y <= 0:
		return
	var aspect := viewport_size.x / viewport_size.y
	var board_extent := float(NetworkManager.local_board.size if NetworkManager.local_board != null else 15) \
			* BOARD_RENDERER.TILE_SIZE + BOARD_RENDERER.CARD_MARGIN
	# The camera looks down at a steep -62 degree pitch, so the board's depth
	# is heavily foreshortened on screen - fitting to the raw board_extent (as
	# if viewed from straight above) left the whole board looking tiny with a
	# huge unused margin. These tighter factors zoom in close to the actual
	# foreshortened silhouette while still leaving the HUD's screen corners clear.
	var vertical_fit := board_extent * 0.72
	var horizontal_fit := (board_extent * 0.95) / maxf(aspect, 0.75)
	_camera.size = maxf(vertical_fit, horizontal_fit)
	_camera.position = Vector3(0, board_extent * 1.25, board_extent * 0.66)

func _setup_particles() -> void:
	if GameConfig.effects_quality < 2 or DisplayServer.get_name() == "headless":
		return
	var particles := GPUParticles3D.new()
	particles.amount = 54
	particles.lifetime = 8.0
	particles.randomness = 0.85
	particles.visibility_aabb = AABB(Vector3(-12, 0, -12), Vector3(24, 10, 24))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(9.0, 2.5, 9.0)
	process.direction = Vector3(0.15, 1.0, 0.05)
	process.spread = 45.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.09
	process.gravity = Vector3.ZERO
	process.scale_min = 0.015
	process.scale_max = 0.045
	process.color = Color(1.0, 0.79, 0.42, 0.22)
	particles.process_material = process
	var draw_mesh := SphereMesh.new()
	draw_mesh.radius = 0.025
	draw_mesh.height = 0.05
	particles.draw_pass_1 = draw_mesh
	particles.position.y = 1.4
	add_child(particles)

func _setup_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	layer.name = "CinematicOverlay"
	add_child(layer)
	var vignette := ColorRect.new()
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = VIGNETTE_SHADER
	material.set_shader_parameter("strength", 0.34)
	vignette.material = material
	layer.add_child(vignette)

func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.name = "HudLayer"
	add_child(layer)
	var hud := HUD_SCRIPT.new()
	hud.name = "Hud"
	layer.add_child(hud)

func _shader_material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
