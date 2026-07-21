class_name PackManifest
extends RefCounted
## Parsed representation of a pack's pack.json manifest.

var id: String = ""
var display_name: String = ""
var version: String = "0.0.0"
var api_version: int = 0
var dependencies: PackedStringArray = []
var load_after: PackedStringArray = []
## Ids of packs whose content this pack intends to override (full conversion).
var replaces: PackedStringArray = []
## Path (relative to the pack root) of an optional GDScript entry point.
var entry: String = ""
## category -> relative directory that holds *.json content files.
var content_dirs: Dictionary = {}
## Logical entry-point scenes a full-conversion pack replaces.
var scene_overrides: Dictionary = {}
## Extra pack-owned resource directories included in the desync signature.
var resource_dirs: PackedStringArray = []

## Absolute-ish resource path of the pack root (res:// or user://).
var root_path: String = ""
## True when the pack lives under user:// (a user-installed mod/DLC).
var is_user_mod: bool = false

static func from_dict(data: Dictionary, root: String, user_mod: bool) -> PackManifest:
	var m := PackManifest.new()
	m.id = str(data.get("id", ""))
	m.display_name = str(data.get("name", m.id))
	m.version = str(data.get("version", "0.0.0"))
	m.api_version = int(data.get("api_version", 0))
	m.dependencies = PackedStringArray(data.get("dependencies", []))
	m.load_after = PackedStringArray(data.get("load_after", []))
	m.replaces = PackedStringArray(data.get("replaces", []))
	m.entry = str(data.get("entry", ""))
	m.content_dirs = data.get("content", {})
	m.scene_overrides = data.get("scene_overrides", {})
	m.resource_dirs = PackedStringArray(data.get("resources", []))
	m.root_path = root
	m.is_user_mod = user_mod
	return m

func is_valid() -> bool:
	return id != "" and api_version > 0

func to_summary() -> Dictionary:
	return {
		"id": id,
		"version": version,
		"api_version": api_version,
	}
