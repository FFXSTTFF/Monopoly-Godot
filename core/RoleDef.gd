class_name RoleDef
extends RefCounted
## Role definitions are data-driven; this helper reads the common fields
## packs store in content/roles/*.json.

static func from_dict(def: Dictionary) -> Dictionary:
	return {
		"id": ContentDef.full_id(def),
		"name": ContentDef.get_string(def, "name", "Role"),
		"description": ContentDef.get_string(def, "description", ""),
		"tags": def.get("tags", []),
		"hooks": def.get("hooks", {}),
	}

static func is_default(def: Dictionary) -> bool:
	return "default" in def.get("tags", [])
