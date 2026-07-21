extends Node
## Central content database populated by the ModLoader.
##
## Everything is addressed by a namespaced id: "packId:localId" (e.g.
## "core:cell_start"). Later-loaded packs may overwrite an existing id, which is
## how a full-conversion DLC can replace the base game.

const CATEGORIES: Array[String] = ["cells", "tokens", "roles", "rulesets", "cards", "sounds"]

## category -> { "packId:localId": Dictionary(content) }
var _content: Dictionary = {}

## Ordered list of loaded pack manifests (see PackManifest).
var loaded_packs: Array = []

## Deterministic signature of the whole loaded set, used by the netcode.
var signature: String = ""
## Logical scene key -> {path, pack_id}. Later packs override earlier ones.
var _scene_overrides: Dictionary = {}

func _ready() -> void:
	reset()

func reset() -> void:
	_content.clear()
	for category in CATEGORIES:
		_content[category] = {}
	loaded_packs.clear()
	signature = ""
	_scene_overrides.clear()

## Registers one content definition. `def` must contain at least "id".
## `pack_id` is the owning pack; the stored full id becomes "pack_id:id" unless
## the def already carries a namespaced id.
func register(category: String, pack_id: String, def: Dictionary) -> String:
	assert(_content.has(category), "Unknown content category: %s" % category)
	var local_id: String = str(def.get("id", ""))
	assert(local_id != "", "Content in pack '%s' is missing an id" % pack_id)
	var full_id: String = local_id if local_id.contains(":") else "%s:%s" % [pack_id, local_id]
	def["full_id"] = full_id
	def["pack_id"] = pack_id
	if not def.has("tags"):
		def["tags"] = []
	_content[category][full_id] = def
	return full_id

func has(category: String, full_id: String) -> bool:
	return _content.has(category) and _content[category].has(full_id)

func get_def(category: String, full_id: String) -> Dictionary:
	if not has(category, full_id):
		return {}
	return _content[category][full_id]

func get_all(category: String) -> Array:
	if not _content.has(category):
		return []
	return _content[category].values()

## Returns every def in `category` that carries `tag` in its "tags" array.
func get_by_tag(category: String, tag: String) -> Array:
	return get_all(category).filter(func(def): return tag in def.get("tags", []))

func category_count(category: String) -> int:
	if not _content.has(category):
		return 0
	return _content[category].size()

func register_scene_override(key: String, path: String, pack_id: String) -> void:
	if key == "" or path == "":
		return
	_scene_overrides[key] = {"path": path, "pack_id": pack_id}

func resolve_scene(key: String, fallback: String) -> String:
	if not _scene_overrides.has(key):
		return fallback
	var path := str(_scene_overrides[key].get("path", fallback))
	if ResourceLoader.exists(path):
		return path
	push_error("[Packs] Scene override '%s' does not exist: %s" % [key, path])
	return fallback

func get_scene_overrides() -> Dictionary:
	return _scene_overrides.duplicate(true)
