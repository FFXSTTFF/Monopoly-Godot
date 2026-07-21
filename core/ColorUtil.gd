class_name ColorUtil
extends RefCounted
## Small helper: content defines colors as hex strings ("#rrggbb"), while local
## customization may already store a Color. Normalize both to a Color.

static func to_color(value, fallback: Color = Color.WHITE) -> Color:
	if value is Color:
		return value
	if value is String and value != "":
		return Color.html(value)
	if value is Array and value.size() >= 3:
		return Color(value[0], value[1], value[2], value[3] if value.size() > 3 else 1.0)
	return fallback
