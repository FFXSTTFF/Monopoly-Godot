extends Node
## Resolves and caches pack-relative 3D assets (.glb/.gltf/.tscn) for modding.
##
## Lets pack content (tokens, cells, rulesets) reference a custom model instead
## of the built-in procedural geometry. Any failure (missing file, bad path,
## unknown extension) returns null so callers can fall back to their existing
## procedural rendering - a broken mod asset must never crash the client.

## abs_path -> PackedScene, or null for a path that failed to load (negative cache).
var _cache: Dictionary = {}
## abs_path -> Texture2D, or null for a path that failed to load (negative cache).
var _texture_cache: Dictionary = {}
var _placeholder_icon: Texture2D

func reset() -> void:
	_cache.clear()
	_texture_cache.clear()

## Resolves `rel_path` against the root of the pack `pack_id` (as recorded in
## PackRegistry.loaded_packs). Rejects ".." segments so a mod cannot reach
## outside its own pack folder. Absolute res:// / user:// paths pass through.
func resolve_path(pack_id: String, rel_path: String) -> String:
	if rel_path == "":
		return ""
	if rel_path.contains(".."):
		push_warning("[AssetLoader] Rejected path escaping pack root: %s" % rel_path)
		return ""
	if rel_path.begins_with("res://") or rel_path.begins_with("user://"):
		return rel_path
	for manifest in PackRegistry.loaded_packs:
		if manifest.id == pack_id:
			return "%s/%s" % [manifest.root_path, rel_path]
	return ""

## Entry point for renderers: loads (with caching) the asset referenced by
## `def[field]`, resolved against `def["pack_id"]`, and returns a fresh
## instance ready to add_child(). Returns null if the field is empty, the
## asset failed to load, or its root isn't a 3D node.
func instantiate_from_def(def: Dictionary, field: String) -> Node3D:
	var rel_path := str(def.get(field, ""))
	if rel_path == "":
		return null
	var pack_id := str(def.get("pack_id", ""))
	var abs_path := resolve_path(pack_id, rel_path)
	if abs_path == "":
		return null
	var packed := _load_packed_scene(abs_path)
	if packed == null:
		return null
	var instance := packed.instantiate()
	var instance_3d := instance as Node3D
	if instance_3d == null:
		push_warning("[AssetLoader] Model root is not a Node3D: %s" % abs_path)
		instance.queue_free()
		return null
	_autoplay(instance_3d)
	return instance_3d

## Loads (with caching) a texture referenced by `def[field]`, resolved against
## `def["pack_id"]`. Falls back to a generic placeholder icon - never null -
## so board tiles always have a reserved spot for a future logo, even before
## a pack supplies one.
func texture_from_def(def: Dictionary, field: String) -> Texture2D:
	var rel_path := str(def.get(field, ""))
	if rel_path == "":
		return _placeholder_texture()
	var pack_id := str(def.get("pack_id", ""))
	var abs_path := resolve_path(pack_id, rel_path)
	if abs_path == "":
		return _placeholder_texture()
	if _texture_cache.has(abs_path):
		var cached: Texture2D = _texture_cache[abs_path]
		return cached if cached != null else _placeholder_texture()
	var image := Image.new()
	var texture: Texture2D = null
	if image.load(abs_path) == OK:
		texture = ImageTexture.create_from_image(image)
	else:
		push_warning("[AssetLoader] Could not load texture: %s" % abs_path)
	_texture_cache[abs_path] = texture
	return texture if texture != null else _placeholder_texture()

## A generic circular emblem generated once and shared by every property that
## doesn't (yet) supply its own icon - reserves the same visual slot a real
## brand logo will later occupy.
func _placeholder_texture() -> Texture2D:
	if _placeholder_icon != null:
		return _placeholder_icon
	const SIZE := 128
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.16, 0.15, 0.13, 0.85))
	var center := Vector2(SIZE / 2.0, SIZE / 2.0)
	var radius := SIZE * 0.32
	for y in SIZE:
		for x in SIZE:
			if Vector2(x, y).distance_to(center) <= radius:
				image.set_pixel(x, y, Color(0.55, 0.47, 0.32, 0.9))
	_placeholder_icon = ImageTexture.create_from_image(image)
	return _placeholder_icon

func _load_packed_scene(abs_path: String) -> PackedScene:
	if _cache.has(abs_path):
		return _cache[abs_path]
	var extension := abs_path.get_extension().to_lower()
	var packed: PackedScene = null
	match extension:
		"tscn", "scn":
			var resource := load(abs_path)
			if resource is PackedScene:
				packed = resource
		"glb", "gltf":
			packed = _load_gltf(abs_path)
		_:
			push_warning("[AssetLoader] Unsupported model extension: %s" % abs_path)
	if packed == null:
		push_warning("[AssetLoader] Could not load model: %s" % abs_path)
	_cache[abs_path] = packed
	return packed

func _load_gltf(abs_path: String) -> PackedScene:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(abs_path, state) != OK:
		return null
	var scene := document.generate_scene(state)
	if scene == null:
		return null
	var packed := PackedScene.new()
	var ok := packed.pack(scene) == OK
	scene.queue_free()
	return packed if ok else null

func _autoplay(instance: Node) -> void:
	var player := _find_animation_player(instance)
	if player == null or player.get_animation_list().is_empty():
		return
	var animation_name: String = player.get_animation_list()[0]
	player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	player.play(animation_name)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
