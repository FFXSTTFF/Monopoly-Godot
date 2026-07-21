extends Node
## Runtime pack/DLC loader.
##
## Scans pack directories, resolves load order from dependencies, registers all
## content into PackRegistry, runs each pack's GDScript entry point, then
## computes a deterministic signature of the whole set. Server and client both
## run this; the signature is compared on connect to prevent version desync.

## Bump when the pack API changes in an incompatible way. Packs declare the
## api_version they target and are rejected if it does not match.
const API_VERSION: int = 2

## Directories scanned for packs, in this order. Later dirs win on id clashes,
## so user mods can override built-in packs (full conversion).
const PACK_DIRS: Array[String] = ["res://packs", "res://mods", "user://mods"]

var _entry_instances: Array = []
var loaded: bool = false

func _ready() -> void:
	_ensure_user_mods_dir()

func _ensure_user_mods_dir() -> void:
	if not DirAccess.dir_exists_absolute("user://mods"):
		DirAccess.make_dir_recursive_absolute("user://mods")

## Loads every discovered pack. Returns the resulting signature.
func load_all() -> String:
	PackRegistry.reset()
	AssetLoader.reset()
	EventBus.clear_hooks()
	_entry_instances.clear()

	var manifests: Array[PackManifest] = _discover_manifests()
	var ordered: Array[PackManifest] = _resolve_order(manifests)

	for manifest in ordered:
		_load_pack_content(manifest)
		_register_scene_overrides(manifest)
		PackRegistry.loaded_packs.append(manifest)

	# Entry scripts run after ALL content is registered, so a pack may safely
	# reference content contributed by its dependencies.
	for manifest in ordered:
		_run_entry(manifest)

	PackRegistry.signature = _compute_signature(ordered)
	loaded = true
	EventBus.packs_loaded.emit(PackRegistry.signature)
	print("[ModLoader] Loaded %d pack(s), signature=%s" % [ordered.size(), PackRegistry.signature])
	return PackRegistry.signature

# --- Discovery ----------------------------------------------------------------

func _discover_manifests() -> Array[PackManifest]:
	var result: Array[PackManifest] = []
	for base_dir in PACK_DIRS:
		if not DirAccess.dir_exists_absolute(base_dir):
			continue
		var is_user: bool = base_dir.begins_with("user://")
		var dir := DirAccess.open(base_dir)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if dir.current_is_dir() and not name.begins_with("."):
				var pack_root := "%s/%s" % [base_dir, name]
				var manifest := _read_manifest(pack_root, is_user)
				if manifest != null:
					result.append(manifest)
			name = dir.get_next()
		dir.list_dir_end()
	return result

func _read_manifest(pack_root: String, is_user: bool) -> PackManifest:
	var manifest_path := "%s/pack.json" % pack_root
	if not FileAccess.file_exists(manifest_path):
		return null
	var data = _read_json(manifest_path)
	if not (data is Dictionary):
		push_error("[ModLoader] Invalid manifest: %s" % manifest_path)
		return null
	var manifest := PackManifest.from_dict(data, pack_root, is_user)
	if not manifest.is_valid():
		push_error("[ModLoader] Manifest missing id/api_version: %s" % manifest_path)
		return null
	if manifest.api_version != API_VERSION:
		push_error("[ModLoader] Pack '%s' targets api_version %d, engine is %d - skipping." % [
			manifest.id, manifest.api_version, API_VERSION])
		return null
	return manifest

# --- Load order (topological over dependencies + load_after) ------------------

func _resolve_order(manifests: Array[PackManifest]) -> Array[PackManifest]:
	var by_id: Dictionary = {}
	for m in manifests:
		by_id[m.id] = m # later dirs overwrite earlier ones on clashing ids

	var visited: Dictionary = {}
	var in_progress: Dictionary = {}
	var ordered: Array[PackManifest] = []

	var visit := func(mid: String, self_ref: Callable) -> void:
		if visited.has(mid) or not by_id.has(mid):
			return
		if in_progress.has(mid):
			push_error("[ModLoader] Dependency cycle involving '%s'" % mid)
			return
		in_progress[mid] = true
		var m: PackManifest = by_id[mid]
		var prereqs: Array = []
		prereqs.append_array(m.dependencies)
		prereqs.append_array(m.load_after)
		for dep in prereqs:
			if not by_id.has(dep) and dep in m.dependencies:
				push_error("[ModLoader] Pack '%s' requires missing dependency '%s'" % [mid, dep])
			self_ref.call(dep, self_ref)
		in_progress.erase(mid)
		visited[mid] = true
		ordered.append(m)

	var ids := by_id.keys()
	ids.sort()
	for mid in ids:
		visit.call(mid, visit)
	return ordered

# --- Content loading ----------------------------------------------------------

func _load_pack_content(manifest: PackManifest) -> void:
	for category in PackRegistry.CATEGORIES:
		if not manifest.content_dirs.has(category):
			continue
		var rel_dir: String = str(manifest.content_dirs[category])
		var dir_path := "%s/%s" % [manifest.root_path, rel_dir]
		for file_path in _list_json_files(dir_path):
			var data = _read_json(file_path)
			if data is Dictionary:
				PackRegistry.register(category, manifest.id, data)
			elif data is Array:
				for entry in data:
					if entry is Dictionary:
						PackRegistry.register(category, manifest.id, entry)

func _run_entry(manifest: PackManifest) -> void:
	if manifest.entry == "":
		return
	var entry_path := "%s/%s" % [manifest.root_path, manifest.entry]
	var script := _load_gdscript(entry_path)
	if script == null:
		push_error("[ModLoader] Could not load entry script: %s" % entry_path)
		return
	var instance = script.new()
	if instance is Node:
		add_child(instance)
	_entry_instances.append(instance)
	if instance.has_method("setup"):
		# Pack code talks to the game via the autoload singletons + EventBus hooks.
		instance.call("setup", manifest.id)

func _register_scene_overrides(manifest: PackManifest) -> void:
	for key_value in manifest.scene_overrides.keys():
		var key := str(key_value)
		var path := str(manifest.scene_overrides[key_value])
		if not path.begins_with("res://") and not path.begins_with("user://"):
			path = "%s/%s" % [manifest.root_path, path]
		PackRegistry.register_scene_override(key, path, manifest.id)

# --- Signature ----------------------------------------------------------------

func _compute_signature(ordered: Array[PackManifest]) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("api:%d" % API_VERSION).to_utf8_buffer())
	for manifest in ordered:
		var header := "|pack:%s@%s:%d" % [manifest.id, manifest.version, manifest.api_version]
		ctx.update(header.to_utf8_buffer())
		# Hash every content file + entry so byte-level changes are detected.
		var files: Array[String] = ["%s/pack.json" % manifest.root_path]
		for category in manifest.content_dirs.keys():
			var dir_path := "%s/%s" % [manifest.root_path, str(manifest.content_dirs[category])]
			files.append_array(_list_pack_files(dir_path))
		for resource_dir in manifest.resource_dirs:
			files.append_array(_list_pack_files("%s/%s" % [manifest.root_path, resource_dir]))
		for override_value in manifest.scene_overrides.values():
			var override_path := str(override_value)
			if not override_path.begins_with("res://") and not override_path.begins_with("user://"):
				override_path = "%s/%s" % [manifest.root_path, override_path]
			files.append(override_path)
		if manifest.entry != "":
			files.append("%s/%s" % [manifest.root_path, manifest.entry])
		files.sort()
		for f in files:
			var file_hash := _file_sha256(f)
			var relative_path := f.trim_prefix(manifest.root_path + "/")
			ctx.update(("|f:%s=%s" % [relative_path, file_hash]).to_utf8_buffer())
	return ctx.finish().hex_encode()

## Public summary used in the network handshake / desync diffing.
func get_pack_summaries() -> Array:
	var out: Array = []
	for m in PackRegistry.loaded_packs:
		out.append(m.to_summary())
	return out

# --- Low-level helpers --------------------------------------------------------

func _read_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("[ModLoader] JSON parse error in %s" % path)
	return parsed

func _list_json_files(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var lower := name.to_lower()
			# Godot appends .import/.remap to res:// resources; ignore those.
			if lower.ends_with(".json"):
				out.append("%s/%s" % [dir_path, name])
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out

## Signature input includes referenced media, not only JSON definitions.
func _list_pack_files(dir_path: String) -> Array[String]:
	var output: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return output
	var directory := DirAccess.open(dir_path)
	if directory == null:
		return output
	directory.list_dir_begin()
	var name := directory.get_next()
	while name != "":
		if name.begins_with("."):
			name = directory.get_next()
			continue
		var path := "%s/%s" % [dir_path, name]
		if directory.current_is_dir():
			output.append_array(_list_pack_files(path))
		elif not name.ends_with(".import") and not name.ends_with(".remap"):
			output.append(path)
		name = directory.get_next()
	directory.list_dir_end()
	output.sort()
	return output

func _file_sha256(path: String) -> String:
	if FileAccess.file_exists(path):
		var h := FileAccess.get_sha256(path)
		if h != "":
			return h
	# Fallback for freshly compiled/streamed files.
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "missing"
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()

func _load_gdscript(path: String) -> GDScript:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is GDScript:
			return res
	# Runtime compilation, needed for scripts under user:// (installed mods).
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var src := f.get_as_text()
	f.close()
	var script := GDScript.new()
	script.source_code = src
	if script.reload() != OK:
		return null
	return script
