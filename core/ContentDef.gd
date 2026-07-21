class_name ContentDef
extends RefCounted
## Thin helpers for pack content dictionaries loaded by ModLoader.

static func full_id(def: Dictionary) -> String:
	return str(def.get("full_id", def.get("id", "")))

static func has_tag(def: Dictionary, tag: String) -> bool:
	return tag in def.get("tags", [])

static func get_string(def: Dictionary, key: String, fallback: String = "") -> String:
	return str(def.get(key, fallback))

static func get_int(def: Dictionary, key: String, fallback: int = 0) -> int:
	return int(def.get(key, fallback))
