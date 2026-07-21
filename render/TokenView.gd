class_name TokenView
extends Node3D
## Layered luxury token assembled from primitives with animated turn halo.

const GOLD_SHADER := preload("res://render/shaders/gold.gdshader")
const DESIGN_HEIGHT := 0.72

var peer_id := 0
var _body_root: Node3D
var _halo: MeshInstance3D
var _body_material: StandardMaterial3D
var _highlight_tween: Tween

func setup(token_def: Dictionary, customization: Dictionary) -> void:
	if _body_root != null:
		_body_root.queue_free()
	_body_root = Node3D.new()
	_body_root.name = "TokenBody"
	add_child(_body_root)
	_body_material = null

	var custom := AssetLoader.instantiate_from_def(token_def, "model")
	if custom != null:
		# Custom models are static: no color/finish tinting, author-authored look.
		_body_root.add_child(custom)
	else:
		var kind := str(token_def.get("mesh", "cylinder"))
		var base_color := ColorUtil.to_color(token_def.get("color", "#c79b3b"))
		var color := ColorUtil.to_color(customization.get("color", base_color), base_color)
		var finish := str(customization.get("material", "polished"))
		_body_material = _make_body_material(color, finish)
		_add_base()
		_add_shape(kind)
	_add_halo()
	scale = Vector3.ONE

func set_highlighted(enabled: bool) -> void:
	if _halo == null:
		return
	if _highlight_tween != null:
		_highlight_tween.kill()
	_halo.visible = enabled
	if _body_material != null:
		_body_material.emission = _body_material.albedo_color * (0.34 if enabled else 0.06)
	if enabled and not GameConfig.reduced_motion:
		_halo.scale = Vector3.ONE
		_highlight_tween = create_tween().set_loops()
		_highlight_tween.tween_property(_halo, "scale", Vector3.ONE * 1.17, 0.72).set_trans(Tween.TRANS_SINE)
		_highlight_tween.tween_property(_halo, "scale", Vector3.ONE, 0.72).set_trans(Tween.TRANS_SINE)

func _add_base() -> void:
	var base := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.29
	mesh.bottom_radius = 0.34
	mesh.height = 0.12
	base.mesh = mesh
	base.position.y = 0.06
	base.material_override = _body_material
	_body_root.add_child(base)

	var collar := MeshInstance3D.new()
	var collar_mesh := TorusMesh.new()
	collar_mesh.inner_radius = 0.23
	collar_mesh.outer_radius = 0.28
	collar.mesh = collar_mesh
	collar.position.y = 0.14
	collar.material_override = _gold_material()
	_body_root.add_child(collar)

func _add_shape(kind: String) -> void:
	var main := MeshInstance3D.new()
	main.mesh = _build_mesh(kind, DESIGN_HEIGHT)
	main.position.y = 0.15 + DESIGN_HEIGHT * 0.5
	main.material_override = _body_material
	_body_root.add_child(main)

	match kind:
		"box":
			# Small cabin turns the primitive into a readable car silhouette.
			var cabin := MeshInstance3D.new()
			var cabin_mesh := BoxMesh.new()
			cabin_mesh.size = Vector3(0.28, 0.26, 0.30)
			cabin.mesh = cabin_mesh
			cabin.position = Vector3(0, 0.57, -0.03)
			cabin.material_override = _body_material
			_body_root.add_child(cabin)
			for x in [-0.22, 0.22]:
				for z in [-0.18, 0.18]:
					_add_wheel(Vector3(x, 0.23, z))
		"capsule":
			# Compact head and ears share the same fixed silhouette bounds.
			var head := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.16
			sphere.height = 0.32
			head.mesh = sphere
			head.position = Vector3(0, 0.76, -0.05)
			head.material_override = _body_material
			_body_root.add_child(head)
			for side in [-1.0, 1.0]:
				var ear := MeshInstance3D.new()
				var ear_mesh := BoxMesh.new()
				ear_mesh.size = Vector3(0.08, 0.20, 0.07)
				ear.mesh = ear_mesh
				ear.position = head.position + Vector3(0.16 * side, -0.04, 0)
				ear.rotation.z = 0.32 * side
				ear.material_override = _body_material
				_body_root.add_child(ear)
		"cone":
			# Gold mast for a ship-like silhouette.
			var mast := MeshInstance3D.new()
			var mast_mesh := CylinderMesh.new()
			mast_mesh.top_radius = 0.025
			mast_mesh.bottom_radius = 0.025
			mast_mesh.height = 0.48
			mast.mesh = mast_mesh
			mast.position = Vector3(0, 0.72, 0)
			mast.material_override = _gold_material()
			_body_root.add_child(mast)
		_:
			pass

func _add_wheel(position: Vector3) -> void:
	var wheel := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.07
	mesh.bottom_radius = 0.07
	mesh.height = 0.05
	wheel.mesh = mesh
	wheel.position = position
	wheel.rotation_degrees.z = 90
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#1a1713")
	material.roughness = 0.6
	wheel.material_override = material
	_body_root.add_child(wheel)

func _add_halo() -> void:
	_halo = MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.37
	mesh.outer_radius = 0.42
	_halo.mesh = mesh
	_halo.position.y = 0.025
	_halo.material_override = _gold_material()
	_halo.visible = false
	_body_root.add_child(_halo)

func _make_body_material(color: Color, finish: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	match finish:
		"brushed":
			material.metallic = 0.68
			material.roughness = 0.48
		"enamel":
			material.metallic = 0.18
			material.roughness = 0.19
		_:
			material.metallic = 0.78
			material.roughness = 0.18
	material.emission_enabled = true
	material.emission = color * 0.06
	return material

func _gold_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GOLD_SHADER
	return material

func _build_mesh(kind: String, height: float) -> Mesh:
	match kind:
		"box":
			var box := BoxMesh.new()
			box.size = Vector3(0.52, height * 0.55, 0.38)
			return box
		"capsule":
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.20
			capsule.height = maxf(height, 0.42)
			return capsule
		"cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.04
			cone.bottom_radius = 0.31
			cone.height = height
			return cone
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = height * 0.44
			sphere.height = height * 0.88
			return sphere
		_:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.24
			cylinder.bottom_radius = 0.27
			cylinder.height = height
			return cylinder
