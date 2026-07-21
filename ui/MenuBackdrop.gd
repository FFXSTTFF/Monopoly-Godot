class_name MenuBackdrop
extends Control
## Lightweight animated luxury backdrop: felt, table geometry and dust motes.

var _time := 0.0
var _motes: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 42:
		_motes.append({
			"uv": Vector2(randf(), randf()),
			"speed": randf_range(0.003, 0.012),
			"phase": randf() * TAU,
			"size": randf_range(0.8, 2.2),
		})
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, UiPalette.INK)

	# Deep felt field with layered translucent bands.
	var center := size * Vector2(0.32, 0.52)
	var radius: float = maxf(size.x, size.y) * 0.82
	for i in range(18, 0, -1):
		var t := float(i) / 18.0
		var color := UiPalette.FELT_DARK.lerp(UiPalette.FELT, 1.0 - t)
		color.a = 0.12
		draw_circle(center, radius * t, color)

	# Perspective board watermark.
	var board_center := Vector2(size.x * 0.30, size.y * 0.58)
	var board_size: float = minf(size.x * 0.54, size.y * 0.68)
	var diamond := PackedVector2Array([
		board_center + Vector2(0, -board_size * 0.42),
		board_center + Vector2(board_size * 0.60, 0),
		board_center + Vector2(0, board_size * 0.42),
		board_center + Vector2(-board_size * 0.60, 0),
	])
	draw_colored_polygon(diamond, Color(UiPalette.MAHOGANY, 0.28))
	draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color(UiPalette.GOLD, 0.22), 2.0, true)
	var inner := PackedVector2Array()
	for point in diamond:
		inner.append(board_center.lerp(point, 0.72))
	draw_polyline(inner + PackedVector2Array([inner[0]]), Color(UiPalette.GOLD, 0.13), 1.0, true)

	# Fine gold architecture lines.
	draw_line(Vector2(48, 54), Vector2(size.x - 48, 54), Color(UiPalette.GOLD, 0.18), 1.0)
	draw_line(Vector2(48, size.y - 54), Vector2(size.x - 48, size.y - 54), Color(UiPalette.GOLD, 0.10), 1.0)

	# Dust suspended in warm light.
	for mote in _motes:
		var uv: Vector2 = mote["uv"]
		var y := fposmod(uv.y - _time * float(mote["speed"]), 1.0)
		var x := uv.x + sin(_time * 0.35 + float(mote["phase"])) * 0.015
		var alpha := 0.08 + 0.13 * (0.5 + 0.5 * sin(_time + float(mote["phase"])))
		draw_circle(Vector2(x * size.x, y * size.y), float(mote["size"]), Color(UiPalette.GOLD_LIGHT, alpha))
